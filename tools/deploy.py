"""Build an app on the Mac build server and install it on the iPhone 4S.

Usage: python tools/deploy.py [trackbag|mapbag|gpsbag]   (default: trackbag)
trackbag = the featured navigator (app/); gpsbag = the zero-interaction
raw readout (rawapp/), which inherited the GPS Bag name.
Pipeline: sync sources -> Mac, make test && make (armv7, iOS 8), pull the
bundle back, push to the phone's /Applications, pseudo-sign with ldid,
refresh SpringBoard.
"""
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
CFG = str(ROOT / "ssh_config")
APPS = {
    "trackbag": {"dir": "app", "bundle": "TrackBag.app", "bin": "TrackBag"},
    "mapbag": {"dir": "mapapp", "bundle": "MapBag.app", "bin": "MapBag"},
    "gpsbag": {"dir": "rawapp", "bundle": "GPSBag.app", "bin": "GPSBag"},
    "devicebag": {"dir": "deviceapp", "bundle": "DeviceBag.app", "bin": "DeviceBag"},
}
# ld64 mislabels the old-format SDK stubs as Simulator; harmless, hide it.
NOISE = ("built for iOS Simulator",)


def run(*args):
    print("+", " ".join(args))
    p = subprocess.run(args, text=True, capture_output=True)
    out = (p.stdout or "") + (p.stderr or "")
    shown = "\n".join(l for l in out.splitlines()
                      if not any(n in l for n in NOISE))
    if shown.strip():
        print(shown)
    if p.returncode:
        sys.exit(f"failed with exit {p.returncode}")


def ssh(host, cmd):
    run("ssh", "-F", CFG, host, cmd)


if __name__ == "__main__":
    name = sys.argv[1] if len(sys.argv) > 1 else "trackbag"
    if name not in APPS:
        sys.exit(f"usage: deploy.py [{'|'.join(APPS)}]")
    app = APPS[name]
    src, bundle, binary = app["dir"], app["bundle"], app["bin"]

    # 1. fresh source copies on the Mac, so local deletions propagate
    # (shared/ rides along at the path the Makefiles expect: ios/shared)
    ssh("mac", f"rm -rf ios/{src} ios/shared")
    run("scp", "-r", "-F", CFG, str(ROOT / "shared"), "mac:ios/shared")
    run("scp", "-r", "-F", CFG, str(ROOT / src), f"mac:ios/{src}")

    # 2. unit tests gate the build: broken logic must never reach the phone
    ssh("mac", f"cd ios/{src} && make test && make")

    # 3. relay the bundle through this PC (the Mac has no key to the phone)
    tmp = pathlib.Path(tempfile.mkdtemp(prefix=f"{name}_"))
    try:
        run("scp", "-r", "-F", CFG, f"mac:ios/{src}/build/{bundle}",
            str(tmp / bundle))

        # 4. install, pseudo-sign, register with SpringBoard
        # -O: classic scp protocol; the phone's OpenSSH 6.7 sftp-server
        # cannot canonicalize not-yet-existing directory targets.
        ssh("iphone", f"rm -rf /Applications/{bundle}")
        run("scp", "-O", "-r", "-F", CFG, str(tmp / bundle),
            f"iphone:/Applications/{bundle}")
        ssh("iphone", f"ldid -S /Applications/{bundle}/{binary}"
                      f" && chmod 755 /Applications/{bundle}/{binary}"
                      f" && uicache")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print(f"deployed - tap the {bundle[:-4]} icon on the phone")
