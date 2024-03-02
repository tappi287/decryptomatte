import ctypes
import struct

import mmh3


def normalize_channel_name(channel_name: str) -> str:
    """ CryptoMaterial.r -> CryptoMaterial.R """
    # Expected is layerName.R .G .B but e.g. Blender creates layerName.r .g .b .a
    if channel_name[-2:] in ('.r', '.g', '.b', '.a'):
        return channel_name[:-2] + channel_name[-2:].upper()
    return channel_name


def hex_str_to_id(id_hex_string: str) -> float:
    """ Converts a manifest hex string to a float32 id value """
    packed = struct.Struct("=I").pack(int(id_hex_string, 16))
    return struct.Struct("=f").unpack(packed)[0]


def id_to_hex_str(id_float: float) -> str:
    return "{0:08x}".format(struct.unpack('<I', struct.pack('<f', id_float))[0])


def id_to_rgb(id_float):
    """ This takes the hashed id and converts it to a preview color """
    bits = ctypes.cast(ctypes.pointer(ctypes.c_float(id_float)), ctypes.POINTER(ctypes.c_uint32)).contents.value

    mask = 2 ** 32 - 1
    return [0.0, float((bits << 8) & mask) / float(mask), float((bits << 16) & mask) / float(mask)]


def mm3hash_float(name) -> float:
    hash_32 = mmh3.hash(name)
    exp = hash_32 >> 23 & 255
    if (exp == 0) or (exp == 255):
        hash_32 ^= 1 << 23

    packed = struct.pack('<L', hash_32 & 0xffffffff)
    return struct.unpack('<f', packed)[0]


def layer_hash(layer_name):
    """ Convert a layer name to hash hex string """
    return id_to_hex_str(mm3hash_float(layer_name))[:-1]
