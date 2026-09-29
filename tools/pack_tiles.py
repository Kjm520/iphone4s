"""Pack the harvested MBTiles for the phone.

The harvester keeps the database in WAL journal mode for write speed, but
iOS 8's SQLite (3.8.x) cannot open a WAL-flagged file read-only, so every
copy shipped to the phone must be rewritten in the classic journal mode.
VACUUM INTO also compacts it in the same pass.

Usage: python tools/pack_tiles.py <output.mbtiles>
"""
import pathlib
import sqlite3
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "tiles" / "usgs_topo.mbtiles"

if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    out = pathlib.Path(sys.argv[1])
    out.unlink(missing_ok=True)
    db = sqlite3.connect(SRC)
    db.execute("VACUUM INTO ?", (str(out),))   # fresh file, DELETE journal
    db.close()
    check = sqlite3.connect(out)
    mode = check.execute("PRAGMA journal_mode").fetchone()[0]
    n, size = check.execute(
        "SELECT COUNT(*), COALESCE(SUM(LENGTH(tile_data)), 0) FROM tiles"
    ).fetchone()
    check.close()
    print(f"packed {n} tiles, {size / 1e9:.2f} GB payload, "
          f"journal={mode}, file={out.stat().st_size / 1e9:.2f} GB")
    assert mode == "delete", "pack failed to clear WAL mode"
