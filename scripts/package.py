"""Build a reproducible addon-only ZIP using Python's standard library."""
from pathlib import Path
import hashlib
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / "ClearLoot"
TOC = ADDON / "ClearLoot.toc"


def build():
    toc = TOC.read_text(encoding="utf-8")
    match = re.search(r"^## Version:\s*([\w.-]+)\s*$", toc, re.MULTILINE)
    if not match:
        raise ValueError("ClearLoot.toc needs a package-safe version")
    paths = {TOC, ADDON / "README.txt"}
    for line in toc.splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            path = (ADDON / line).resolve()
            path.relative_to(ADDON.resolve())
            if not path.is_file():
                raise FileNotFoundError(f"Missing TOC dependency: {line}")
            paths.add(path)
    destination = ROOT / "dist" / f"ClearLoot-{match.group(1)}.zip"
    destination.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(paths):
            member = "ClearLoot/" + path.relative_to(ADDON).as_posix()
            info = zipfile.ZipInfo(member, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, path.read_bytes())
    with zipfile.ZipFile(destination) as archive:
        assert archive.testzip() is None
        assert "ClearLoot/ClearLoot.toc" in archive.namelist()
    digest = hashlib.sha256(destination.read_bytes()).hexdigest()
    print(f"Built {destination.relative_to(ROOT)} ({destination.stat().st_size} bytes)")
    print(f"SHA-256: {digest}")
    return destination


if __name__ == "__main__":
    build()
