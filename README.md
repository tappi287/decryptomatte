# Decryptomatte

This package works with Cryptomatte images, extracting and manipulating individual layers and their coverage information. It incorporates elements from the original `cryptomatte_arnold` unit tests, licensed under BSD-3 [https://github.com/Psyop/CryptomatteArnold](https://github.com/Psyop/CryptomatteArnold).

![Example](tests/data/input/Titleimg.webp)
[Artwork by dj3dim](https://blendswap.com/blend/26178)

## Installation

#### Install via pip
While you can install this package from PyPi via pip
`pip install decryptomatte`
You'll most likely miss the required binary OpenImageIO wheel for your platform.

#### Install in virtual environment
On Windows, you can however clone this repository and install a binary OpenImageIO wheel from my private package index:
1. Get [Python](https://python.org) version > 3.9, tested with 3.11
2. `git clone https://github.com/tappi287/decryptomatte.git`
3. Install [poetry](https://python-poetry.org/docs/main/#installation)
4. Navigate to the repository directory `cd decryptomatte`
5. Run `poetry install`

You should now be able to import and use this package inside your poetry/virtual environment.

### Example

The package contains a convenience script to extract all masks to individual image files. Usage is show below.
``` python
from pathlib import Path

from decryptomatte import cryptomatte_to_images

if __name__ == '__main__':
    input_dir = Path('test/data/input')
    output_dir = input_dir / 'out'
    
    sample_matte_img = input_dir / 'BlenderExample.exr'
    sample_beauty_img = input_dir / 'BlenderExample.exr'

    cryptomatte_to_images(sample_matte_img, sample_beauty_img, output_dir=output_dir)
```

## Usage

1. **Importing the Class:**

```python
from decryptomatte import Decrypt
```

2. **Creating an Instance:**

* **Basic Instance:**

```python
my_object = Decrypt("path/to/your/cryptomatte_image.exr")
```

* **Instance with Arguments:**

```python
my_object = Decrypt("path/to/your/cryptomatte_image.exr", alpha_over_compositing=True)
```

- `alpha_over_compositing` (optional, default `False`) specifies handling alpha over compositing during certain operations.

**Accessing Attributes:**

While the class defines internal attributes, use the provided methods to interact with the object.

**Methods:**

* **`list_layers()`:** Returns available Cryptomatte layer names (IDs).
* **`crypto_metadata()`:** Returns extracted Cryptomatte metadata.
* **`sorted_crypto_metadata()`:** Returns sorted Cryptomatte metadata with ID coverage information.
* **`get_cryptomatte_channels()`:** Returns a NumPy array containing all Cryptomatte image channels.
* **`get_mattes_by_names(layer_names: List[str]) -> dict`:** Retrieves coverage mattes for specified layer names (IDs).
* **`_get_mattes_by_ids(target_ids: List[float]) -> Dict[float, np.ndarray]`:** (internal) Gets individual alpha coverage mattes for IDs.
* **`get_masks_for_ids(target_ids: List[float]) -> Generator[Tuple[float, np.ndarray], None, None]`:** (internal) Generates individual masks (anti-aliased) for each object ID.
* **`get_mask_for_id(float_id: float, channels_arr: np.ndarray, level: int = 6, as_8bit=False) -> np.ndarray`:** (internal) Extracts the mask for a specific ID from Cryptomatte layers.
* **`_iterate_image(width: int, height: int, target_ids: list) -> Dict[float, np.ndarray]`:** (internal) Iterates through all image pixels, collecting coverage values for specified IDs.
* **`id_to_name(self, id_float: float) -> str`:** Returns the human-readable layer name for the provided ID.
* **`create_layer_object_name(self, id_float: float) -> str`:** Creates a human-readable name combining the layer, ID, and object name.
* **`get_id_from_readable_layer_name(self, readable_layer_name: str) -> Optional[float]`:** Attempts to extract the ID from a human-readable layer name.
* **`merge_matte_and_id_color(self, matte: np.ndarray, id_float: Optional[float] = None, layer_name: Optional[str] = None) -> np.ndarray`:** Creates an RGBA image by combining the provided matte with its corresponding ID color.
* **`merge_matte_and_rgb(matte: np.ndarray, rgb_img: np.ndarray = None) -> np.ndarray`:** (static) Merges a matte with an optional RGB image, creating an RGBA image.
* **`shutdown()`:** Releases OpenImageIO resources
