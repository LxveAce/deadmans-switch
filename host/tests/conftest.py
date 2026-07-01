# conftest.py -- put host/ on sys.path so `import provision` works when pytest is run from the
# repo root or from host/. Stdlib-only; no board, no NVS generator, no network.
import os
import sys

_HOST_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _HOST_DIR not in sys.path:
    sys.path.insert(0, _HOST_DIR)
