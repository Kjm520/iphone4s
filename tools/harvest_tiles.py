"""Harvest USGS Topo tiles into an MBTiles file for the offline Map Bag app.

Usage:
    python tools/harvest_tiles.py                 # all phases, resumable
    python tools/harvest_tiles.py --phases base   # just the named phases

Phases (coarse-to-fine so a partial harvest is already useful):
    base       CONUS z0-8      (~1.3k tiles)  whole-country overview
    conus      CONUS z9-11     (~83k tiles)   every highway and town
    southeast  SE US z12-13    (~77k tiles)   every road, LA -> Carolinas
    alabama    AL+buffer z14   (~57k tiles)   full topo detail near home

Safe to stop (Ctrl-C) and re-run: finished tiles and permanent 404s are
skipped on resume. 8 parallel fetchers; backs off globally on 429/5xx.
"""
import argparse
import math
import pathlib
import sqlite3
import sys
import threading
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

URL = ("https://basemap.nationalmap.gov/arcgis/rest/services/"
       "USGSTopo/MapServer/tile/{z}/{y}/{x}")
UA = "MapBagHarvester/1.0 (personal offline archive)"
DB_PATH = pathlib.Path(__file__).resolve().parent.parent / "tiles" / "usgs_topo.mbtiles"
WORKERS = 8
COMMIT_EVERY = 256

#            name        west    south  east    north   zmin zmax
PHASES = [("base",      (-125.0, 24.0, -66.0,  50.0),   0,  8),
          ("conus",     (-125.0, 24.0, -66.0,  50.0),   9, 11),
          ("southeast", (-92.0,  28.8, -78.5,  36.8),  12, 13),
          ("alabama",   (-88.8,  29.9, -84.6,  35.35), 14, 14)]

throttle = threading.Event()


def tile_range(bbox, z):
    """Inclusive (x0, x1, y0, y1) covering bbox at zoom z (XYZ scheme)."""
    west, south, east, north = bbox
    n = 1 << z

    def x_of(lon):
        return min(n - 1, max(0, int((lon + 180.0) / 360.0 * n)))

    def y_of(lat):
        y = (1.0 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2.0
        return min(n - 1, max(0, int(y * n)))

    return x_of(west), x_of(east), y_of(north), y_of(south)   # y grows south


def open_db():
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(DB_PATH)
    db.executescript("""
        PRAGMA journal_mode = WAL;
        PRAGMA synchronous = NORMAL;
        CREATE TABLE IF NOT EXISTS tiles (
            zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER,
            tile_data BLOB,
            PRIMARY KEY (zoom_level, tile_column, tile_row));
        CREATE TABLE IF NOT EXISTS misses (
            z INTEGER, x INTEGER, y INTEGER, PRIMARY KEY (z, x, y));
        CREATE TABLE IF NOT EXISTS metadata (name TEXT PRIMARY KEY, value TEXT);
    """)
    db.executemany(
        "INSERT OR REPLACE INTO metadata VALUES (?, ?)",
        [("name", "USGS Topo offline"), ("format", "jpg"),
         ("minzoom", "0"), ("maxzoom", "14"),
         ("bounds", "-125,24,-66,50"),
         ("attribution", "USGS The National Map")])
    db.commit()
    return db


def fetch(key):
    """Return (key, bytes | None); None marks a permanent miss (404)."""
    z, x, y = key
    req = urllib.request.Request(URL.format(z=z, y=y, x=x),
                                 headers={"User-Agent": UA})
    for attempt in range(5):
        if throttle.is_set():
            time.sleep(5)
            throttle.clear()
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return key, r.read()
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return key, None
            if e.code in (429, 500, 502, 503):
                throttle.set()          # everyone slows down together
        except OSError:
            pass
        time.sleep(2 ** attempt)
    raise RuntimeError(f"gave up on {key}")


def harvest_phase(db, name, bbox, zmin, zmax):
    have = {(z, x, y) for z, x, y in db.execute(
        "SELECT zoom_level, tile_column, (1 << zoom_level) - 1 - tile_row "
        "FROM tiles WHERE zoom_level BETWEEN ? AND ?", (zmin, zmax))}
    have |= {(z, x, y) for z, x, y in db.execute(
        "SELECT z, x, y FROM misses WHERE z BETWEEN ? AND ?", (zmin, zmax))}

    todo = []
    for z in range(zmin, zmax + 1):
        x0, x1, y0, y1 = tile_range(bbox, z)
        todo += [(z, x, y)
                 for x in range(x0, x1 + 1)
                 for y in range(y0, y1 + 1)
                 if (z, x, y) not in have]
    total, done, misses, byte_count = len(todo), 0, 0, 0
    print(f"[{name}] {total} tiles to fetch "
          f"({len(have)} already present)", flush=True)
    if not todo:
        return

    started = time.time()
    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        for key, data in pool.map(fetch, todo, chunksize=16):
            z, x, y = key
            if data is None:
                db.execute("INSERT OR IGNORE INTO misses VALUES (?,?,?)",
                           (z, x, y))
                misses += 1
            else:
                db.execute("INSERT OR REPLACE INTO tiles VALUES (?,?,?,?)",
                           (z, x, ((1 << z) - 1) - y, sqlite3.Binary(data)))
                byte_count += len(data)
            done += 1
            if done % COMMIT_EVERY == 0:
                db.commit()
            if done % 2000 == 0:
                rate = done / max(1e-9, time.time() - started)
                print(f"[{name}] {done}/{total}  {byte_count / 1e6:.0f} MB  "
                      f"{rate:.0f} tiles/s  eta {(total - done) / rate / 60:.0f} min",
                      flush=True)
    db.commit()
    print(f"[{name}] DONE: {done} fetched, {misses} empty (404), "
          f"{byte_count / 1e6:.0f} MB, {(time.time() - started) / 60:.1f} min",
          flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--phases", default=",".join(p[0] for p in PHASES),
                    help="comma-separated subset of phases to run")
    args = ap.parse_args()
    wanted = set(args.phases.split(","))
    unknown = wanted - {p[0] for p in PHASES}
    if unknown:
        sys.exit(f"unknown phase(s): {unknown}")

    db = open_db()
    try:
        for name, bbox, zmin, zmax in PHASES:
            if name in wanted:
                harvest_phase(db, name, bbox, zmin, zmax)
    except KeyboardInterrupt:
        print("\ninterrupted - progress saved; re-run to resume", flush=True)
    finally:
        db.commit()
        n, size = db.execute(
            "SELECT COUNT(*), COALESCE(SUM(LENGTH(tile_data)), 0) FROM tiles"
        ).fetchone()
        print(f"database now holds {n} tiles, {size / 1e9:.2f} GB", flush=True)
        db.close()


if __name__ == "__main__":
    main()
