"""Shared helpers for winlauncher: ids, PE headers, engine detection, state paths.

Read-only with respect to game folders: nothing here writes or opens a game file
for writing.
"""
import hashlib
import json
import os
import struct
from pathlib import Path

HOME = Path.home()
WL_DATA = Path(os.environ.get("WL_DATA", HOME / ".local/share/winlauncher"))
WL_STATE = Path(os.environ.get("WL_STATE", HOME / ".local/state/winlauncher"))

# Executables that are never the game itself
HELPER_WORDS = ("unitycrashhandler", "crashpad_handler", "notification_helper", "unins",
                "setup", "config.exe", "dxsetup", "vc_redist", "vcredist", "redist",
                "console.exe", "launcherhelper", "ue4prereq")


def game_id(folder: Path) -> str:
    """Same rule as bin/winrun: sha256 of the absolute folder path, 16 hex chars."""
    return hashlib.sha256(str(Path(folder).resolve()).encode("utf-8")).hexdigest()[:16]


def pe_info(path: Path):
    """Return dict(arch=, sections=[...]) or None if not a PE file."""
    try:
        with open(path, "rb") as f:
            head = f.read(0x1000)
    except OSError:
        return None
    if head[:2] != b"MZ" or len(head) < 0x40:
        return None
    off = struct.unpack_from("<I", head, 0x3C)[0]
    if off + 24 > len(head) or head[off:off + 4] != b"PE\0\0":
        return None
    machine, nsect = struct.unpack_from("<HH", head, off + 4)
    opt_size = struct.unpack_from("<H", head, off + 20)[0]
    sec_tab = off + 24 + opt_size
    sections = []
    for i in range(min(nsect, 64)):
        s = sec_tab + i * 40
        if s + 8 > len(head):
            break
        sections.append(head[s:s + 8].rstrip(b"\0").decode("latin-1"))
    arch = {0x8664: "x64", 0x14C: "x86", 0xAA64: "arm64"}.get(machine, f"0x{machine:04x}")
    return {"arch": arch, "sections": sections}


def tail_bytes(path: Path, n: int) -> bytes:
    try:
        with open(path, "rb") as f:
            f.seek(0, os.SEEK_END)
            size = f.tell()
            f.seek(max(0, size - n))
            return f.read()
    except OSError:
        return b""


def is_helper(name: str) -> bool:
    n = name.lower()
    return any(w in n for w in HELPER_WORDS)


def candidate_exes(root: Path, max_depth=3):
    out = []
    root = Path(root)
    for dirpath, dirnames, filenames in os.walk(root):
        depth = len(Path(dirpath).relative_to(root).parts)
        # never descend into engine/plugin internals
        dirnames[:] = [d for d in dirnames
                       if depth < max_depth and not d.endswith("_Data")
                       and d not in ("BepInEx", "MonoBleedingEdge", "www", "locales", "resources",
                                     "swiftshader", "_CommonRedist", "Redist")]
        for fn in filenames:
            if fn.lower().endswith(".exe"):
                out.append(Path(dirpath) / fn)
    return out


def pick_main_exe(root: Path):
    """Best guess at the game's own exe. Unity: the exe with a matching <name>_Data."""
    exes = [p for p in candidate_exes(root) if not is_helper(p.name)]
    if not exes:
        return None
    for p in exes:
        if (p.parent / f"{p.stem}_Data").is_dir():
            return p
    for p in exes:
        if p.name.lower() == "game.exe":
            return p
    # shallowest first, then largest
    return sorted(exes, key=lambda p: (len(p.relative_to(root).parts), -p.stat().st_size))[0]


def detect_engine(exe: Path):
    """Return dict(engine=, detail=, layer=) for the folder containing exe."""
    d = exe.parent
    names = {p.name.lower(): p for p in d.iterdir()}
    data = d / f"{exe.stem}_Data"
    if not data.is_dir():
        data = next((p for p in d.iterdir() if p.is_dir() and p.name.endswith("_Data")
                     and (p / "globalgamemanagers").exists()), None)
    if data and data.is_dir():
        il2cpp = (d / "GameAssembly.dll").exists() or (data / "il2cpp_data").is_dir()
        mono = (data / "Managed" / "Assembly-CSharp.dll").exists()
        unity_ver = unity_version(data)
        flavour = "IL2CPP" if il2cpp else ("Mono" if mono else "unknown")
        return {"engine": f"Unity {flavour}", "detail": unity_ver or "", "data_dir": str(data)}
    if any(n.endswith(".pck") for n in names) or tail_bytes(exe, 4) == b"GDPC":
        emb = tail_bytes(exe, 4) == b"GDPC"
        return {"engine": "Godot", "detail": "pck embedded in exe" if emb else "separate .pck"}
    for base in (d / "www", d):
        if (base / "js" / "rmmz_core.js").exists():
            return {"engine": "RPG Maker MZ", "detail": rel(base / "data", d)}
        if (base / "js" / "rpg_core.js").exists():
            return {"engine": "RPG Maker MV", "detail": rel(base / "data", d)}
    if (d / "resources" / "app.asar").exists():
        return {"engine": "Electron", "detail": "resources/app.asar"}
    if (d / "resources" / "app").is_dir():
        return {"engine": "Electron", "detail": "resources/app/ (unpacked)"}
    if "nw.pak" in names or "package.nw" in names or "nw.dll" in names:
        return {"engine": "NW.js", "detail": "package.nw" if "package.nw" in names else "nw.pak"}
    wolf_files = [n for n in names if n.endswith(".wolf")]
    if (d / "Data").is_dir():
        wolf_files += [p.name for p in (d / "Data").iterdir() if p.suffix.lower() == ".wolf"]
    if wolf_files or "guruguru smf4.dll" in names or "gurugurusmf4.dll" in names:
        return {"engine": "WolfRPG",
                "detail": f"{len(wolf_files)} .wolf archive(s)" if wolf_files else "loose Data/"}
    if "game.rgss3a" in names or any(n.startswith("rgss3") and n.endswith(".dll") for n in names):
        return {"engine": "RPG Maker VX Ace", "detail": ""}
    if (d / "renpy").is_dir():
        return {"engine": "Ren'Py", "detail": ""}
    tail = tail_bytes(exe, 8)
    if len(tail) == 8 and tail[:4] == b"\x56\x34\x12\xfa":
        return {"engine": "Flash projector", "detail": "SWF appended to exe"}
    info = pe_info(exe) or {}
    secs = [s.lower() for s in info.get("sections", [])]
    if any(s.startswith(".enigma") for s in secs):
        return {"engine": "packed (Enigma Virtual Box)", "detail": "unpack before any text work"}
    if "setup" in exe.name.lower():
        return {"engine": "installer", "detail": ""}
    return {"engine": "unknown", "detail": ""}


def rel(p: Path, base: Path):
    try:
        return str(p.relative_to(base))
    except ValueError:
        return str(p)


def unity_version(data_dir: Path):
    """Read the Unity version string from globalgamemanagers / data.unity3d header."""
    for name in ("globalgamemanagers", "data.unity3d", "mainData"):
        p = Path(data_dir) / name
        if not p.exists():
            continue
        try:
            with open(p, "rb") as f:
                head = f.read(0x80)
        except OSError:
            continue
        # serialized file: version string sits after a small binary header
        import re
        m = re.search(rb"(20\d\d\.\d+\.\d+[abfp]\d+|[56]\.\d+\.\d+[abfp]\d+)", head)
        if m:
            return m.group(1).decode()
    return None


def translation_state(game_dir: Path):
    """Describe what translation machinery is present in a game folder (read-only)."""
    g = Path(game_dir)
    st = {"bepinex": None, "xunity": False, "endpoint": None, "lines": 0, "manifest": False}
    core = g / "BepInEx" / "core"
    if (core / "BepInEx.Core.dll").exists() or (core / "BepInEx.Unity.IL2CPP.dll").exists():
        st["bepinex"] = "6"
    elif (core / "BepInEx.dll").exists():
        st["bepinex"] = "5"
    plug = g / "BepInEx" / "plugins"
    if plug.is_dir():
        st["xunity"] = any(plug.rglob("XUnity.AutoTranslator.Plugin.Core.dll"))
    cfg = g / "BepInEx" / "config" / "AutoTranslatorConfig.ini"
    if cfg.exists():
        sec = None
        # XUnity saves this file with a UTF-8 BOM; utf-8-sig strips it
        for ln in cfg.read_text(encoding="utf-8-sig", errors="replace").splitlines():
            s = ln.strip()
            if s.startswith("["):
                sec = s
            elif sec == "[Service]" and s.startswith("Endpoint="):
                st["endpoint"] = s.split("=", 1)[1]
    tdir = g / "BepInEx" / "Translation" / "en" / "Text"
    if tdir.is_dir():
        for f in tdir.glob("*.txt"):
            try:
                st["lines"] += sum(1 for ln in f.open(encoding="utf-8", errors="replace")
                                   if "=" in ln and not ln.startswith("//"))
            except OSError:
                pass
    st["manifest"] = (g / ".winlauncher-translate.json").exists()
    return st


def launcher_state(folder: Path):
    gid = game_id(folder)
    st = {"id": gid, "prefix": (WL_DATA / "prefixes" / gid / ".winlauncher-ready").exists(),
          "last": None}
    runs = WL_STATE / "games" / gid / "runs.tsv"
    if runs.exists():
        lines = runs.read_text(encoding="utf-8", errors="replace").strip().splitlines()
        if lines:
            f = lines[-1].split("\t")
            st["last"] = {"when": f[0], "rc": f[2].replace("rc=", ""), "secs": f[3].rstrip("s")}
    return st


def load_json(p: Path, default=None):
    try:
        return json.loads(Path(p).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return default
