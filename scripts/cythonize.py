import pathlib
import subprocess

from Cython.Build import cythonize

if __name__ == "__main__":
    base_path = pathlib.Path(__file__).parents[1]
    module = base_path / 'src' / 'decryptomatte' / 'decrypt.pyx'
    cythonize([module.as_posix()])
    p = subprocess.Popen(['cythonize', '-i', module.as_posix()])
