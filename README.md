# Decryptomatte
Extract Cryptomatte information and masks from EXR image files.

## Usage


## Example
```
from pathlib import Path

from decryptomatte import cryptomatte_to_images

if __name__ == '__main__':
    input_dir = Path(__file__).parent
    output_dir = input_dir / 'out'
    
    sample_matte_img = input_dir / 'BlenderExample.exr'
    sample_beauty_img = input_dir / 'BlenderExample.exr'

    cryptomatte_to_images(sample_matte_img, sample_beauty_img, output_dir=output_dir)
```