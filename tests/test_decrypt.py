import logging
from pathlib import Path

from decryptomatte import cryptomatte_to_images

logging.basicConfig(level=logging.DEBUG, format="%(asctime)s %(module)s %(levelname)s: %(message)s")


def test_decrypt_example():
    current_dir = Path(__file__).parent
    current_output_dir = current_dir / 'data' / 'output'
    input_dir = current_dir / 'data' / 'input'
    current_output_dir.mkdir(exist_ok=True)

    sample_matte_img = input_dir / 'BlenderExample.exr'
    sample_beauty_img = input_dir / 'BlenderExample.exr'

    cryptomatte_to_images(sample_matte_img, sample_beauty_img, output_dir=current_output_dir)
