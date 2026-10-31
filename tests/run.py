from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / "tools" / "python"))
from lupa import LuaRuntime

import os
os.chdir(root)
lua = LuaRuntime()
lua.execute((root / "tests" / "test_camera_patch.lua").read_text(encoding="utf-8"))
print(LuaRuntime().execute((root / "tests" / "test_runtime.lua").read_text(encoding="utf-8")))
