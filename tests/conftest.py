from pathlib import Path

import pytest


@pytest.fixture
def test_data_input_dir():
    return Path(__file__).parent / 'data' / 'input'


@pytest.fixture
def test_data_output_dir():
    out_dir = Path(__file__).parent / 'data' / 'output'
    out_dir.mkdir(exist_ok=True)
    return out_dir
