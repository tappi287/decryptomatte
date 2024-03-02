import logging
from pathlib import Path
from typing import Optional

import numpy as np

import OpenImageIO
from OpenImageIO import ImageBufAlgo, ImageOutput, ImageSpec, ImageBuf


class OpenImageUtil:
    @classmethod
    def get_image_resolution(cls, img_file: Path) -> (int, int):
        img_input = cls._image_input(img_file)

        if img_input:
            res_x, res_y = img_input.spec().width, img_input.spec().height
            img_input.close()
            del img_input
            return res_x, res_y
        return 0, 0

    @classmethod
    def premultiply_image(cls, img_pixels: np.array) -> np.array:
        """ Premultiply a numpy image with itself """
        a = cls.np_to_imagebuf(img_pixels)
        ImageBufAlgo.premult(a, a)

        return a.get_pixels(a.spec().format, a.spec().roi_full)

    @staticmethod
    def get_numpy_oiio_img_format(np_array: np.ndarray):
        """ Returns either float or 8 bit integer format"""
        img_format = OpenImageIO.FLOAT
        if np_array.dtype != np.float32:
            img_format = OpenImageIO.UINT8

        return img_format

    @classmethod
    def np_to_imagebuf(cls, img_pixels: np.array):
        """ Load a numpy array 8/32bit to oiio ImageBuf """
        if len(img_pixels.shape) < 3:
            logging.error('Can not create image with pixel data in this shape. Expecting 4 channels(RGBA).')
            return

        h, w, c = img_pixels.shape
        img_spec = ImageSpec(w, h, c, cls.get_numpy_oiio_img_format(img_pixels))

        img_buf = ImageBuf(img_spec)
        img_buf.set_pixels(img_spec.roi_full, img_pixels)

        return img_buf

    @classmethod
    def _image_input(cls, img_file: Path) -> Optional[OpenImageIO.ImageInput]:
        """ CLOSE the returned object after usage! """
        img_input = OpenImageIO.ImageInput.open(img_file.as_posix())

        if img_input is None:
            logging.error('Error reading image: %s', OpenImageIO.geterror())
            return
        return img_input

    @classmethod
    def read_image(cls, img_file: Path, img_format: str = '') -> Optional[np.array]:
        img_input = cls._image_input(img_file)

        if not img_input:
            return None

        # Read out image data as numpy array
        img = img_input.read_image(format=img_format)
        img_input.close()

        return img

    @classmethod
    def write_image(cls, file: Path, pixels: np.array):
        output = ImageOutput.create(file.as_posix())

        if not output:
            logging.error('Error creating oiio image output:\n%s', OpenImageIO.geterror())
            return

        if len(pixels.shape) < 3:
            logging.error('Can not create image with Pixel data in this shape. Expecting 3 or 4 channels(RGB, RGBA).')
            return

        h, w, c = pixels.shape
        spec = ImageSpec(w, h, c, cls.get_numpy_oiio_img_format(pixels))

        result = output.open(file.as_posix(), spec)
        if result:
            try:
                output.write_image(pixels)
            except Exception as e:
                logging.error('Could not write Image: %s', e)
        else:
            logging.error('Could not open image file for writing: %s: %s', file.name, output.geterror())

        output.close()
