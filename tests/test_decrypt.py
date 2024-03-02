import logging
from pathlib import Path
from typing import Optional, Union

from decryptomatte.decrypt import Decrypt
from decryptomatte.open_image_util import OpenImageUtil
from decryptomatte.utils import create_file_safe_name

logging.basicConfig(level=logging.DEBUG, format="%(asctime)s %(module)s %(levelname)s: %(message)s")


def decryptomatte_example(matte_img_file: Union[Path, str],
                          beauty_img_file: Optional[Union[Path, str]] = None,
                          out_img_format='.png',
                          output_dir: Optional[Path] = None):
    """

    :param beauty_img_file:
    :param matte_img_file:
    :param out_img_format:
    :param output_dir:
    :return:
    """
    beauty_img = None
    if beauty_img_file and beauty_img_file.exists():
        beauty_img = OpenImageUtil.read_image(beauty_img_file)
        beauty_img = OpenImageUtil.premultiply_image(beauty_img)

    d = Decrypt(matte_img_file, alpha_over_compositing=True)
    layers = d.list_layers()

    for layer_name, id_matte in d.get_mattes_by_names(layers).items():
        logging.debug('Creating image for layer %s - %s', layer_name, id_matte.any(axis=-1).sum())

        # Create premultiplied
        if beauty_img is not None:
            rgba_matte = d.merge_matte_and_rgb(id_matte, beauty_img)
            repre_matte = OpenImageUtil.premultiply_image(rgba_matte)
        else:
            repre_matte = d.merge_matte_and_id_color(id_matte, layer_name=layer_name)

        # Write result
        file_name = f'{create_file_safe_name(layer_name)}{out_img_format}'
        if output_dir and output_dir.exists():
            pre_img_file = output_dir / file_name
        else:
            pre_img_file = matte_img_file.parent / file_name

        OpenImageUtil.write_image(pre_img_file, repre_matte)

    d.shutdown()

    logging.debug('Example matte extraction finished.')


def test_decrypt_example():
    current_dir = Path(__file__).parent
    current_output_dir = current_dir / 'data' / 'output'
    input_dir = current_dir / 'data' / 'input'
    current_output_dir.mkdir(exist_ok=True)

    sample_matte_img = input_dir / 'BlenderExample.exr'
    sample_beauty_img = input_dir / 'BlenderExample.exr'

    decryptomatte_example(sample_matte_img, sample_beauty_img, output_dir=current_output_dir)
