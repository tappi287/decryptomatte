import logging
from pathlib import Path
from typing import Optional, Union

from decryptomatte.decrypt import Decrypt
from decryptomatte.open_image_util import OpenImageUtil
from decryptomatte.utils import create_file_safe_name

logging.basicConfig(level=logging.DEBUG, format="%(asctime)s %(module)s %(levelname)s: %(message)s")


def cryptomatte_to_images(matte_img_file: Union[Path, str],
                          beauty_img_file: Optional[Union[Path, str]] = None,
                          out_img_format='.png',
                          output_dir: Optional[Path, str] = None,
                          alpha_over_compositing: bool = False):
    """
    Create a single image for every cryptomatte mask. Provide a 'beauty image' to fill the rgb values of
    the resulting mask with a beauty render. Without a beauty image, the rgb values of the matte will be filled with
    the id color, resulting in a 'clown mask'.
    If you plan to use these mask in e.g. Photoshop, set alpha_over_compositing to true.

    Args:
        matte_img_file (Union[Path, str]): Path to the image file containing the Cryptomatte
        beauty_img_file (Union[Path, str]): Optional path to an image file containing a beauty render
        out_img_format (str): File extension of the output mask images. Defaults to '.png'
        output_dir (Path, str):
        alpha_over_compositing (bool, optional):

    Returns:
        None
    """
    # -- Prepare paths
    matte_img_file = Path(matte_img_file)
    if beauty_img_file is not None:
        beauty_img_file = Path(beauty_img_file)

    if output_dir is None:
        output_dir = matte_img_file.parent
    else:
        output_dir = Path(output_dir)
        output_dir.mkdir(exist_ok=True)

    # -- Read the beauty image
    beauty_img = None
    if beauty_img_file and beauty_img_file.exists():
        beauty_img = OpenImageUtil.read_image(beauty_img_file)
        beauty_img = OpenImageUtil.premultiply_image(beauty_img)

    # -- Read the cryptomatte
    d = Decrypt(matte_img_file, alpha_over_compositing=alpha_over_compositing)

    # -- Create a single image file for every matte
    for layer_name, id_matte in d.get_mattes_by_names(d.list_layers()).items():
        logging.debug('Creating image for layer %s - %s', layer_name, id_matte.any(axis=-1).sum())

        if beauty_img is not None:
            # -- Create premultiplied matte
            rgba_matte = d.merge_matte_and_rgb(id_matte, beauty_img)
            repre_matte = OpenImageUtil.premultiply_image(rgba_matte)
        else:
            repre_matte = d.merge_matte_and_id_color(id_matte, layer_name=layer_name)

        # -- Write result
        file_name = f'{create_file_safe_name(layer_name)}{out_img_format}'
        result_img_file = output_dir / file_name
        OpenImageUtil.write_image(result_img_file, repre_matte)

    d.shutdown()

    logging.info('Matte extraction finished.')
