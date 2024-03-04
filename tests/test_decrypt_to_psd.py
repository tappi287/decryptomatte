import numpy as np
from decryptomatte import Decrypt, create_file_safe_name


def test_decrypt(test_data_input_dir, test_data_output_dir):
    """
    Example showing how you could decrypt and write to a PSD file with Photoshop API
    PhotoshopAPI = "^0.3.0"

    :param test_data_input_dir:
    :param test_data_output_dir:
    :return:
    """
    import psapi

    img_file = test_data_input_dir / 'BlenderExample.exr'
    psd_file = test_data_output_dir / 'Test.psd'
    psd_file.unlink(missing_ok=True)

    d = Decrypt(img_file, alpha_over_compositing=False)
    width, height = d.img.spec().width, d.img.spec().height
    color_mode = psapi.enum.ColorMode.rgb
    psd_document = psapi.LayeredFile_8bit(color_mode, width, height)

    for layer_name, id_matte in d.get_mattes_by_names(d.list_layers()).items():
        colored_matte = d.merge_matte_and_id_color(id_matte, layer_name=layer_name)
        # h w c -> c h w
        colored_matte = colored_matte.transpose((2, 0, 1))

        img_layer_8bit = psapi.ImageLayer_8bit(
            np.uint8(colored_matte * 255).copy(),
            create_file_safe_name(layer_name),
            width=width,
            height=height,
            color_mode=color_mode
        )
        psd_document.add_layer(img_layer_8bit)

    psd_document.write(psd_file)
