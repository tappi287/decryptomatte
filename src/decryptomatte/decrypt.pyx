import json
import logging
import cython
import os
from pathlib import Path
from typing import List, Optional, Union, Tuple, Generator, Dict

import numpy as np
import time

import OpenImageIO
import decryptomatte.decrpyt_utils as du


class Decrypt:
    """ A lot of this code is borrowed from original cryptomatte_arnold unit tests under BSD-3 license
        https://github.com/Psyop/CryptomatteArnold
        https://github.com/Psyop/Cryptomatte
    """
    empty_pixel_threshold = 1  # Minimum number of opaque pixels a matte must contain
    empty_value_threshold = 0.01  # Minimum sum of all coverage values of all pixels

    def __init__(self, img_file: Union[Path, str], alpha_over_compositing=False):
        self.alpha_over_compositing = alpha_over_compositing

        self.img_file = Path(img_file)
        self.img = OpenImageIO.ImageBuf(self.img_file.as_posix())
        self._manifest_cache = dict()
        self._metadata = dict()
        self._sorted_metadata = dict()

    @property
    def metadata(self) -> dict:
        if not self._metadata:
            self._metadata = self.crypto_metadata()
        return self._metadata

    @property
    def sorted_metadata(self) -> dict:
        if not self._sorted_metadata:
            self._sorted_metadata = self.sorted_crypto_metadata()
        return self._sorted_metadata

    @property
    def manifest_cache(self) -> dict:
        if not self._manifest_cache:
            self._manifest_cache = self._create_manifest_cache()
        return self._manifest_cache

    def shutdown(self):
        """ Release resources """
        try:
            self.img.clear()
            del self.img
            OpenImageIO.ImageCache().invalidate(self.img_file.as_posix())
        except Exception as e:
            logging.error('Error closing img buf: %s', e)

    def _create_manifest_cache(self):
        """ Store the manifest contents from extracted metadata """
        manifest_cache = dict()

        for k, m in self.metadata.items():
            if not k.endswith('manifest'):
                continue
            named_data = {f"{k.replace('/', '.')}.{n}": v for n, v in json.loads(m).items()}
            manifest_cache.update(named_data)
        return manifest_cache

    def list_layers(self):
        """ List available ID layers of this cryptomatte image """
        layer_names = list()
        logging.info('Found Cryptomatte with %s id layers', len(self.manifest_cache))

        # List ids in cryptomatte
        for layer_name, id_hex_str in self.manifest_cache.items():
            layer_names.append(layer_name)

        return layer_names

    def crypto_metadata(self) -> dict:
        """ Returns dictionary of key, value of cryptomatte metadata """
        metadata = {
            a.name: a.value
            for a in self.img.spec().extra_attribs
            if a.name.startswith("cryptomatte")
        }

        for key in metadata.keys():
            if key.endswith("/manif_file"):
                sidecar_path = os.path.join(
                    os.path.dirname(self.img.name), metadata[key]
                )
                with open(sidecar_path) as f:
                    metadata[key.replace("manif_file", "manifest")] = f.read()

        return metadata

    def sorted_crypto_metadata(self):
        """
        Gets a dictionary of the cryptomatte metadata, interleaved by cryptomatte stream.

        for example:
            {"crypto_object": {"name": crypto_object", ... }}

        Also includes ID coverage pairs in subkeys, "ch_pair_idxs" and "ch_pair_names".
        """
        img_md = self.crypto_metadata()
        cryptomatte_streams = {}

        for key, value in img_md.items():
            prefix, cryp_key, cryp_md_key = key.split("/")
            name = img_md["/".join((prefix, cryp_key, "name"))]
            cryptomatte_streams[name] = cryptomatte_streams.get(name, {})
            cryptomatte_streams[name][cryp_md_key] = value

        for cryp_key in cryptomatte_streams:
            name = cryptomatte_streams[cryp_key]["name"]
            ch_id_coverages = []
            ch_id_coverage_names = []
            channels_dict = {
                du.normalize_channel_name(ch): i
                for i, ch in enumerate(self.img.spec().channelnames)
            }
            for i, ch in enumerate(self.img.spec().channelnames):
                ch = du.normalize_channel_name(ch)

                if not ch.startswith(name):
                    continue

                if ch.startswith("%s." % name):
                    continue

                if ch.endswith(".R"):
                    red_name = ch
                    green_name = "%s.G" % ch[:-2]
                    blue_name = "%s.B" % ch[:-2]
                    alpha_name = "%s.A" % ch[:-2]

                    red_idx = i
                    green_idx = channels_dict[green_name]
                    blue_idx = channels_dict[blue_name]
                    alpha_idx = channels_dict[alpha_name]

                    ch_id_coverages.append((red_idx, green_idx))
                    ch_id_coverages.append((blue_idx, alpha_idx))
                    ch_id_coverage_names.append((red_name, green_name))
                    ch_id_coverage_names.append((blue_name, alpha_name))
            cryptomatte_streams[cryp_key]["ch_pair_idxs"] = ch_id_coverages
            cryptomatte_streams[cryp_key]["ch_pair_names"] = ch_id_coverage_names
        return cryptomatte_streams

    def get_cryptomatte_channels(self):
        """ Get all image channels associated with Cryptomatte as a ndarray """
        channels = list()
        for layer_name, layer_data in self.sorted_metadata.items():
            for ch_start, ch_end in layer_data["ch_pair_idxs"]:
                roi = OpenImageIO.ROI(
                    self.img.roi_full.xbegin, self.img.roi_full.xend,
                    self.img.roi_full.ybegin, self.img.roi_full.yend,
                    self.img.roi_full.zbegin, self.img.roi_full.zend,
                    ch_start, ch_end + 1)
                channel_pair = self.img.get_pixels(OpenImageIO.FLOAT, roi)
                channels.append(channel_pair[:, :, 0])
                channels.append(channel_pair[:, :, 1])

        return np.stack(channels, axis=-1)

    def get_mattes_by_names(self, layer_names: List[str]) -> dict:
        id_to_names = dict()

        for name in layer_names:
            if name in self.manifest_cache:
                id_val = du.hex_str_to_id(self.manifest_cache.get(name))
                id_to_names[id_val] = name

        id_mattes_by_name = dict()
        for id_val, id_matte in self._get_mattes_by_ids(list(id_to_names.keys())).items():
            id_mattes_by_name[
                du.create_layer_object_name(self.sorted_metadata, id_val)
            ] = id_matte

        return id_mattes_by_name

    def _get_mattes_by_ids(self, target_ids: List[float]) -> Dict[float, np.ndarray]:
        """ Get a alpha coverage matte for every given id
            as dict {id_value[float]: coverage_matte[np.array]}

            Matte arrays are single channel two-dimensional arrays(shape: image_height, image_width)
        """
        if not target_ids:
            return dict()
        target_ids = [i for i in target_ids if not np.isnan(i)]

        w, h = self.img.spec().width, self.img.spec().height

        start = time.time()
        if self.alpha_over_compositing:
            id_mattes = self.iterate_image(w, h, target_ids)
        else:
            id_mattes = {k: v for k, v in self.get_masks_for_ids(target_ids)}

        # Purge mattes below threshold value
        purged_matte_names = list()
        for id_val in target_ids:
            v, p = id_mattes[id_val].max(), id_mattes[id_val].any(axis=-1).sum()

            if v < self.empty_value_threshold and p < self.empty_pixel_threshold:
                purged_matte_names.append(f"{v} {p} {self.id_to_name(id_val)}")
                id_mattes.pop(id_val)
        logging.debug(f'Purged empty coverage mattes: {purged_matte_names}')

        # --- DEBUG info ---
        logging.debug(f'Iterated image : {w:04d}x{h:04d} - with {len(target_ids)} ids.')
        logging.debug(f'Id Matte extraction finished in {time.time() - start:.4f}s')

        return id_mattes

    def get_masks_for_ids(self, target_ids: List[float]) -> Generator[Tuple[float, np.ndarray], None, None]:
        """ Get an individual mask of every object in the cryptomatte

        Args:
            target_ids: List of float ids to extract

        Returns:
            (float, numpy.ndarray): Mapping from the float id of each object to
            it's anti-aliased mask.
        """
        channels_arr = self.get_cryptomatte_channels()

        # Number of layers depends on level of cryptomatte. Default level = 6.
        # Each layer has 4 channels: RGBA
        num_layers = channels_arr.shape[2] // 4
        level = 2 * num_layers

        # The objects in manifest are sorted alphabetically to maintain some order.
        # Each obj is assigned an unique ID (per image) for the mask
        for layer in self.sorted_metadata:
            logging.debug('Creating mask for Cryptomatte layer: ' + str(layer))

            for obj_name in sorted(self.manifest_cache.keys()):
                float_id = du.hex_str_to_id(self.manifest_cache[obj_name])
                if float_id not in target_ids:
                    continue

                logging.debug('Reading Object: ' + str(obj_name))
                yield float_id, self.get_mask_for_id(float_id, channels_arr, level)

    def get_mask_for_id(self, float_id: float, channels_arr: np.ndarray, level: int = 6, as_8bit=False) -> np.ndarray:
        """
        Extract mask corresponding to a float id from the cryptomatte layers

        Args:
            float_id (float): The ID of the object (from manifest).
            channels_arr (numpy.ndarray): The cryptomatte layers combined into a single array along the channels axis.
                                         Each layer should be in acsending order with it's channels in RGBA order.
                                         By default, there are 3 layers, corresponding to a level of 6.
            level (int): The Level of the Cryptomatte. Default is 6 for most rendering engines. The level dictates the
                         max num of objects that the crytomatte can represent. The number of cryptomatte layers in EXR
                         will change depending on level.
            as_8bit (bool): return mask as 8 bit image

        Returns:
            numpy.ndarray: Mask from cryptomatte for a given id. Dtype: np.uint8, Range: [0, 255]
        """
        coverage_list = []
        for rank in range(level):
            coverage_rank = self.get_coverage_for_rank(float_id, channels_arr, rank)
            coverage_list.append(coverage_rank)

        coverage = sum(coverage_list)
        coverage = np.clip(coverage, 0.0, 1.0)
        if as_8bit:
            return (coverage * 255).astype(np.uint8)
        return coverage

    @staticmethod
    def get_coverage_for_rank(float_id: float, cr_combined: np.ndarray, rank: int) -> np.ndarray:
        """
        Get the coverage mask for a given rank from cryptomatte layers

        Args:
            float_id (float32): The ID of the object
            cr_combined (numpy.ndarray): The cryptomatte layers combined into a single array along the channels axis.
                                         By default, there are 3 layers, corresponding to a level of 6.
            rank (int): The rank, or level, of the coverage to be calculated

        Returns:
            numpy.ndarray: Mask for given coverage rank. Dtype: np.float32, Range: [0, 1]
        """
        id_rank = (cr_combined[:, :, rank * 2] == float_id)
        coverage_rank = cr_combined[:, :, rank * 2 + 1] * id_rank

        return coverage_rank

    @staticmethod
    @cython.boundscheck(False)
    def iter_pixels(width: int, height: int) -> Generator[Tuple[int, int], None, None]:
        cdef int x, y
        for y in range(height):
            for x in range(width):
                yield x, y

    @cython.boundscheck(False)
    def iterate_image(self, width: int, height: int, target_ids: List[float]) -> Dict[float, np.ndarray]:
        """
        Iterate through every image pixel and get the coverage values for the given target ids. This can
        take alpha over compositing into account. Will set whole pixels opaque if multiple ids are
        contributing to it.

        Args:
            width (int): Image pixel width
            height (int): Image pixel height
            target_ids (list(float)): List of target ids
        Returns:
            dict[(float, numpy.ndarray)]: Mapping from the float id of each object to
            it's anti-aliased mask.
        """
        id_mattes = {id_val: np.zeros((height, width), dtype=np.float32) for id_val in target_ids}

        for x, y in self.iter_pixels(width, height):
            result_pixel = list(self.img.getpixel(x, y))

            for cryp_key in self.sorted_metadata:
                result_id_cov = self._get_id_coverage_dict(
                    result_pixel,
                    self.sorted_metadata[cryp_key]["ch_pair_idxs"]
                )

                high_rank_id, coverage_sum = 0.0, 0.0

                for id_val, coverage in result_id_cov.items():
                    if id_val not in target_ids:
                        continue

                    # Sum coverage per id
                    id_mattes[id_val][y][x] += coverage
                    # Sum overall coverage for this pixel of all ids
                    coverage_sum += coverage

                    if not high_rank_id:
                        # Store the id with the highest rank
                        # for this pixel (first entry in result_id_cov)
                        high_rank_id = id_val

                # Highest ranked Id will be set fully opaque for the whole pixel
                # if multiple Ids are contributing to this pixel
                # getting matte ready for alpha over operations eg. Photoshop
                if self.alpha_over_compositing and high_rank_id:
                    if id_mattes[high_rank_id][y][x] != coverage_sum:
                        id_mattes[high_rank_id][y][x] = coverage_sum

            if not y % 256 and x == 0:
                logging.debug('Reading cryptomatte at vline: %s (%sx%s)', y, width, height)

        return id_mattes

    @staticmethod
    def _get_id_coverage_dict(pixel_values: List[float], ch_pair_idxs: List[int]) -> Dict[float, float]:
        return {
            pixel_values[x]: pixel_values[y]
            for x, y, in ch_pair_idxs if (x != 0 or y != 0)
        }

    def id_to_name(self, id_float: float) -> str:
        hex_str = du.id_to_hex_str(id_float)
        for name, hex_id in self.manifest_cache.items():
            if hex_str == hex_id:
                return name

        return str()

    def get_id_from_readable_layer_name(self, readable_layer_name: str) -> Optional[float]:
        """ Search for hex_id in the readable_layer_name and returns the float id """
        for hex_id in self.manifest_cache.values():
            if f".{hex_id}." in readable_layer_name:
                return du.hex_str_to_id(hex_id)

    def merge_matte_and_id_color(self,
                                 matte: np.ndarray,
                                 id_float: Optional[float] = None,
                                 layer_name: Optional[str] = None) -> np.ndarray:
        """ Create the alpha matte and fill with it's corresponding id color """
        color = [0.5, 0.5, 0.5]

        if layer_name:
            id_float = self.get_id_from_readable_layer_name(layer_name)
        if id_float:
            color = du.id_to_rgb(id_float)

        h, w = matte.shape
        rgba = np.empty((h, w, 4), dtype=matte.dtype)

        rgba[:, :, 3] = matte
        rgba[:, :, 2] = color[2]
        rgba[:, :, 1] = color[1]
        rgba[:, :, 0] = color[0]

        return rgba

    @staticmethod
    def merge_matte_and_rgb(matte: np.ndarray, rgb_img: np.ndarray = None) -> np.ndarray:
        """ Merge matte and rgb img array to rgba img array"""
        h, w = matte.shape
        rgba = np.empty((h, w, 4), dtype=matte.dtype)

        if rgb_img is None:
            rgba[:, :, 3] = rgba[:, :, 2] = rgba[:, :, 1] = rgba[:, :, 0] = matte
        else:
            rgba[:, :, 3] = matte
            rgba[:, :, 2] = rgb_img[:, :, 2]
            rgba[:, :, 1] = rgb_img[:, :, 1]
            rgba[:, :, 0] = rgb_img[:, :, 0]

        return rgba
