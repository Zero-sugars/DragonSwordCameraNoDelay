"""Exercise the same embedded backend used by the GUI, against disposable game folders."""
from pathlib import Path
from contextlib import contextmanager
import ctypes
import hashlib
import json
import os
import subprocess
import sys
import time
import uuid
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
version = ET.parse(root / "src" / "Setup" / "DragonSword.CameraNoDelay.Setup.csproj").findtext(".//Version")
exe = Path(sys.argv[1]).resolve()
fixture_root = Path(os.environ.get('DS_TEST_FIXTURE_ROOT', str(root / 'tests' / 'results')))
fixture_name = "setup-한글 (공백) $literal & " + uuid.uuid4().hex
if os.environ.get('DS_TEST_COMPACT_PATH'):
    fixture_name = "한글 ($literal)& " + uuid.uuid4().hex[:8]
fixture = fixture_root / fixture_name
game_bin = fixture / "DS" / "Binaries" / "Win64"
game_bin.mkdir(parents=True)
(game_bin / "DSClient-Win64-Shipping.exe").write_bytes(b"original game fixture")
(game_bin / "unrelated.txt").write_text("preserve me", encoding="utf-8")
record_path = game_bin / "CameraNoDelay-install-manifest.json"

def invoke(action, ok=True, component=None):
    args = [str(exe), "--action", action, "--game-root", str(fixture)]
    if component: args += ['--component',component]
    process = subprocess.run(args, capture_output=True, encoding="utf-8", timeout=45)
    if not process.stdout.strip():
        raise AssertionError(f"Missing JSON for {action}: {process.stderr}")
    result = json.loads(process.stdout.lstrip("\ufeff"))
    assert result["Ok"] == ok, result
    assert process.returncode == (0 if ok else 1), (process.returncode, result)
    return result

def read_record():
    return json.loads(record_path.read_text(encoding="utf-8-sig"))

def verify_files():
    for entry in read_record()["files"]:
        assert hashlib.sha256((game_bin / entry["path"]).read_bytes()).hexdigest().upper() == entry["sha256"].upper()

def snapshot():
    paths = [record_path] + [game_bin / entry["path"] for entry in read_record()["files"]]
    return {path: path.read_bytes() for path in paths}

@contextmanager
def read_lock(path):
    api = ctypes.WinDLL("kernel32", use_last_error=True)
    api.CreateFileW.argtypes = [ctypes.c_wchar_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_void_p]
    api.CreateFileW.restype = ctypes.c_void_p
    api.CloseHandle.argtypes = [ctypes.c_void_p]
    handle = api.CreateFileW(str(path), 0x80000000, 1, None, 3, 0x80, None)
    if handle == ctypes.c_void_p(-1).value:
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        yield
    finally:
        api.CloseHandle(handle)

assert invoke("Status")["State"] == "not-installed"
# A process with the game's executable name must block mutations.
guard_dir = fixture / "process-guard"
guard_dir.mkdir()
guard_exe = guard_dir / "DSClient.exe"
guard_source = guard_dir / "Program.cs"
guard_source.write_text("class Program { static void Main() { System.Threading.Thread.Sleep(60000); } }", encoding="ascii")
csc = Path(os.environ["WINDIR"]) / "Microsoft.NET" / "Framework64" / "v4.0.30319" / "csc.exe"
compiled = subprocess.run([str(csc), "/nologo", "/target:exe", "/out:" + str(guard_exe), str(guard_source)], capture_output=True, timeout=30)
assert compiled.returncode == 0, compiled.stderr or compiled.stdout
guard = subprocess.Popen([str(guard_exe)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, creationflags=subprocess.CREATE_NO_WINDOW)
try:
    time.sleep(0.3)
    assert guard.poll() is None, "Process-guard fixture exited"
    status = invoke("Status")
    assert status["Running"] and not status["CanInstall"] and not status["CanRemove"]
    invoke("Install", ok=False)
    assert not record_path.exists()
finally:
    guard.kill()
    guard.wait(timeout=10)
invoke("Install")
assert invoke("Status")["Version"] == version
verify_files()
invoke("Remove")
assert not record_path.exists() and not (game_bin / "dwmapi.dll").exists()
assert (game_bin / "unrelated.txt").read_text() == "preserve me"

# Each feature is a real installation subset, sharing the loader until the last removal.
scripts=game_bin/'ue4ss/Mods/DragonSwordCameraNoDelay/Scripts'
invoke('Install',component='Camera')
status=invoke('Status')
assert status['CameraInstalled'] and not status['MenuInstalled'] and len(read_record()['files'])==9
assert (scripts/'camera_patch.lua').exists() and not (scripts/'menu_keyboard.lua').exists()
assert 'camera=true, menu=false' in (scripts/'components.lua').read_text()
camera_bytes=(scripts/'camera_patch.lua').read_bytes()
invoke('Install',component='Menu')
assert invoke('Status')['MenuInstalled'] and (scripts/'camera_patch.lua').read_bytes()==camera_bytes
assert len(read_record()['files'])==13
before=snapshot()
with read_lock(scripts/'camera_patch.lua'):
    invoke('Remove',ok=False,component='Camera')
assert snapshot()==before,'Failed partial removal must restore every file and manifest'
invoke('Remove',component='Camera')
status=invoke('Status');verify_files()
assert status['MenuInstalled'] and not status['CameraInstalled'] and len(read_record()['files'])==12
assert not (scripts/'camera_patch.lua').exists() and (scripts/'menu_keyboard.lua').exists() and (game_bin/'dwmapi.dll').exists()
assert 'camera=false, menu=true' in (scripts/'components.lua').read_text()
invoke('Install',component='Camera')
invoke('Remove',component='Menu')
status=invoke('Status');verify_files()
assert status['CameraInstalled'] and not status['MenuInstalled']
assert not (scripts/'menu_keyboard.lua').exists() and (scripts/'camera_patch.lua').exists()
record_bytes=record_path.read_bytes();tampered=read_record();tampered['components']=['unknown']
record_path.write_text(json.dumps(tampered),encoding='utf-8')
assert invoke('Status')['State']=='conflict'
invoke('Install',ok=False,component='Menu')
record_path.write_bytes(record_bytes)
invoke('Remove',component='Camera')
assert invoke('Status')['State']=='not-installed' and not (game_bin/'dwmapi.dll').exists()

legacy = root / "release" / "DragonSwordCameraNoDelay-v0.1.0"
if legacy.exists():
    windows_ps_env = os.environ.copy()
    windows_ps_env["PSModulePath"] = str(Path(os.environ["WINDIR"]) / "System32" / "WindowsPowerShell" / "v1.0" / "Modules")
    result = subprocess.run(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(legacy / "Manage-Mod.ps1"), "-Action", "Install", "-GameRoot", str(fixture)], capture_output=True, timeout=30, env=windows_ps_env)
    assert result.returncode == 0, result.stderr
    assert invoke("Status")["Version"] == "0.1.0"
    untracked = game_bin / "ue4ss" / "Mods" / "DragonSwordCameraNoDelay" / "Scripts" / "menu_navigation.lua"
    untracked.write_text("foreign file: preserve", encoding="utf-8")
    invoke("Install", ok=False)
    assert untracked.read_text(encoding="utf-8") == "foreign file: preserve"
    assert invoke("Status")["Version"] == "0.1.0"
    untracked.unlink()
    invoke("Install")
    assert invoke("Status")["Version"] == version
    verify_files()
else:
    invoke("Install")
    record = read_record()
    record["version"] = "0.1.0"
    record_path.write_text(json.dumps(record), encoding="utf-8")
    assert invoke("Status")["Version"] == "0.1.0"
    invoke("Install")
    assert invoke("Status")["Version"] == version

# The previous manager's record is compatible with this patch release too.
older_menu = root / 'release' / 'DragonSwordCameraNoDelay-v0.3.0' / 'DragonSword.CameraNoDelay.Setup.exe'
if older_menu.exists():
    invoke('Remove')
    old_install = subprocess.run([str(older_menu), '--action', 'Install', '--game-root', str(fixture)], capture_output=True, encoding='utf-8', timeout=45)
    assert old_install.returncode == 0, old_install.stderr or old_install.stdout
    assert invoke('Status')['Version'] == '0.3.0' and len(read_record()['files']) == 9
    invoke('Install')
    assert invoke('Status')['Version'] == version and len(read_record()['files']) == 13
    verify_files()

previous = root / 'release' / 'DragonSwordCameraNoDelay-v0.3.2' / 'DragonSword.CameraNoDelay.Setup.exe'
if previous.exists():
    invoke('Remove')
    result = subprocess.run([str(previous), '--action', 'Install', '--game-root', str(fixture)], capture_output=True, encoding='utf-8', timeout=45)
    assert result.returncode == 0, result.stderr or result.stdout
    assert invoke('Status')['Version'] == '0.3.2' and len(read_record()['files']) == 10
    untracked = game_bin / 'ue4ss' / 'Mods' / 'DragonSwordCameraNoDelay' / 'Scripts' / 'world_map.lua'
    untracked.write_text('foreign map file',encoding='utf-8')
    invoke('Install',ok=False)
    assert untracked.read_text() == 'foreign map file' and invoke('Status')['Version'] == '0.3.2'
    untracked.unlink()
    invoke('Install')
    assert invoke('Status')['Version'] == version and len(read_record()['files']) == 13
    verify_files()

record = read_record()
record["version"] = "0.2.0"
record_path.write_text(json.dumps(record), encoding="utf-8")
assert invoke("Status")["Version"] == "0.2.0"
invoke("Install")
assert invoke("Status")["Version"] == version

# A missing tracked file can be repaired, and does not prevent removal.
missing = game_bin / read_record()["files"][0]["path"]
missing.unlink()
invoke("Install")
verify_files()

# Simulate a valid older release with different bytes, then deny the last write.
record = read_record()
first = game_bin / record["files"][0]["path"]
first.write_bytes(first.read_bytes() + b"previous-release-fixture")
record["files"][0]["sha256"] = hashlib.sha256(first.read_bytes()).hexdigest().upper()
record_path.write_text(json.dumps(record), encoding="utf-8")
before = snapshot()
locked = game_bin / record["files"][-1]["path"]
with read_lock(locked):
    invoke("Install", ok=False)
assert all(path.read_bytes() == data for path, data in before.items()), "Failed install did not roll back"
with read_lock(locked):
    invoke("Remove", ok=False)
assert all(path.read_bytes() == data for path, data in before.items()), "Failed remove did not roll back"
invoke("Install")
verify_files()

script = game_bin / "ue4ss" / "Mods" / "DragonSwordCameraNoDelay" / "Scripts" / "main.lua"
original = script.read_bytes()
script.write_bytes(original + b"-- externally changed\n")
invoke("Remove", ok=False)
assert record_path.exists() and (game_bin / "dwmapi.dll").exists()
script.write_bytes(original)

foreign = game_bin / "ue4ss" / "Mods" / "OtherMod"
foreign.mkdir()
(foreign / "enabled.txt").write_text("1")
invoke("Remove", ok=False)
assert (foreign / "enabled.txt").exists()
(foreign / "enabled.txt").unlink()
foreign.rmdir()

valid_record = record_path.read_bytes()
record = read_record()
record["files"][0]["path"] = "DSClient-Win64-Shipping.exe"
record_path.write_text(json.dumps(record), encoding="utf-8")
invoke("Remove", ok=False)
assert (game_bin / "DSClient-Win64-Shipping.exe").read_bytes() == b"original game fixture"
record_path.write_bytes(valid_record)
missing.unlink()
invoke("Remove")
assert invoke("Status")["State"] == "not-installed"
assert not (game_bin / "dwmapi.dll").exists()
assert (game_bin / "unrelated.txt").read_text() == "preserve me"
print("setup executable: install/remove, legacy upgrade, running-game block, Korean/literal paths, missing repair/removal, write/move rollback, changed-file/other-mod/manifest protections PASS")
print(f"Fixture retained: {fixture}")
