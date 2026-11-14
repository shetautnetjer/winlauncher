#!/usr/bin/env python3
"""Make winlauncher the default handler for Windows .exe files, or undo it.

  mimeapps.py set     <desktop-id> <state.json> [mimeapps.list]
  mimeapps.py restore <desktop-id> <state.json> [mimeapps.list]
  mimeapps.py show    [mimeapps.list]

Edits only the lines for the MIME types below in ~/.config/mimeapps.list.
`set` records the previous default for each type in state.json and keeps a
one-time copy of the original file next to it; `restore` puts those defaults
back (only for types still pointing at winlauncher) and removes winlauncher
from [Added Associations]. Everything else in the file is left byte-for-byte.
"""
import json
import os
import shutil
import sys
import time
from pathlib import Path

TYPES = [
    "application/vnd.microsoft.portable-executable",  # what xdg-mime reports
    "application/x-msdownload",                       # what GIO/Nautilus reports
    "application/x-ms-dos-executable",                # older alias
]
DEFAULT = "Default Applications"
ADDED = "Added Associations"


def default_path():
    base = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    return Path(base) / "mimeapps.list"


def read_lines(p: Path):
    return p.read_text(encoding="utf-8").splitlines() if p.exists() else []


def find_section(lines, name):
    """Return (start, end) indices of the section body, or None."""
    start = None
    for i, ln in enumerate(lines):
        s = ln.strip()
        if s.startswith("[") and s.endswith("]"):
            if start is not None:
                return start, i
            if s[1:-1] == name:
                start = i + 1
    return (start, len(lines)) if start is not None else None


def get_key(lines, section, key):
    sec = find_section(lines, section)
    if not sec:
        return None
    for i in range(*sec):
        k, sep, v = lines[i].partition("=")
        if sep and k.strip() == key:
            return v.strip()
    return None


def set_key(lines, section, key, value):
    """value None deletes the key. Returns new list."""
    lines = list(lines)
    sec = find_section(lines, section)
    if not sec:
        if value is None:
            return lines
        if lines and lines[-1].strip():
            lines.append("")
        lines += [f"[{section}]", f"{key}={value}"]
        return lines
    for i in range(*sec):
        k, sep, _ = lines[i].partition("=")
        if sep and k.strip() == key:
            if value is None:
                del lines[i]
            else:
                lines[i] = f"{key}={value}"
            return lines
    if value is not None:
        # insert after the last non-blank line of the section
        end = sec[1]
        while end > sec[0] and not lines[end - 1].strip():
            end -= 1
        lines.insert(end, f"{key}={value}")
    return lines


def write_lines(p: Path, lines):
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_name(p.name + ".winlauncher-tmp")
    tmp.write_text("\n".join(lines) + "\n", encoding="utf-8")
    os.replace(tmp, p)


def cmd_set(desktop, state_path: Path, p: Path):
    lines = read_lines(p)
    state = json.loads(state_path.read_text()) if state_path.exists() else {}
    if p.exists() and "backup" not in state:
        bak = p.with_name(f"{p.name}.winlauncher-backup-{time.strftime('%Y%m%d-%H%M%S')}")
        shutil.copy2(p, bak)
        state["backup"] = str(bak)
    prev = state.setdefault("previous_defaults", {})
    for t in TYPES:
        cur = get_key(lines, DEFAULT, t)
        if t not in prev:                       # first install only: remember the original
            prev[t] = cur if cur != desktop else None
        lines = set_key(lines, DEFAULT, t, desktop)
        added = [x for x in (get_key(lines, ADDED, t) or "").split(";") if x]
        if desktop not in added:
            lines = set_key(lines, ADDED, t, ";".join([desktop] + added) + ";")
    write_lines(p, lines)
    state_path.parent.mkdir(parents=True, exist_ok=True)
    state_path.write_text(json.dumps(state, indent=2))
    for t in TYPES:
        print(f"  {t} -> {desktop}   (was: {prev[t] or 'unset'})")


def cmd_restore(desktop, state_path: Path, p: Path):
    lines = read_lines(p)
    state = json.loads(state_path.read_text()) if state_path.exists() else {}
    prev = state.get("previous_defaults", {})
    for t in TYPES:
        if get_key(lines, DEFAULT, t) == desktop:
            lines = set_key(lines, DEFAULT, t, prev.get(t))
            print(f"  {t} -> {prev.get(t) or 'unset'}")
        else:
            print(f"  {t}: default is no longer winlauncher, left as is")
        added = [x for x in (get_key(lines, ADDED, t) or "").split(";") if x and x != desktop]
        lines = set_key(lines, ADDED, t, (";".join(added) + ";") if added else None)
    write_lines(p, lines)
    if state.get("backup"):
        print(f"  original copy kept at {state['backup']}")


def main(argv):
    if len(argv) >= 2 and argv[1] == "show":
        p = Path(argv[2]) if len(argv) > 2 else default_path()
        lines = read_lines(p)
        for t in TYPES:
            print(f"{t}\tdefault={get_key(lines, DEFAULT, t)}\tadded={get_key(lines, ADDED, t)}")
        return 0
    if len(argv) < 4 or argv[1] not in ("set", "restore"):
        print(__doc__, file=sys.stderr)
        return 2
    p = Path(argv[4]) if len(argv) > 4 else default_path()
    (cmd_set if argv[1] == "set" else cmd_restore)(argv[2], Path(argv[3]), p)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
