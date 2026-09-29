"""Complete the theos iPhoneOS9.3.sdk on the build Mac. Run there:

    python3 patch_sdk.py [sdk_path]

The community SDK's text stubs omit some symbols that genuinely exist on
device (first seen: memchr, then strcmp - clang/ld64 need them spelled out
even for the most ordinary libc calls). Rather than dodging each one in
source, append the standard C string/memory set to the libSystem umbrella
stub once. Also installs the liblaunch.tbd stub (see tools/liblaunch.tbd).
Idempotent: a second run changes nothing.
"""
import pathlib
import sys

SDK = pathlib.Path(sys.argv[1] if len(sys.argv) > 1
                   else pathlib.Path.home() / "ios/sdks/iPhoneOS9.3.sdk")

SYMBOLS = [
    "_memccpy", "_memchr", "_memmem", "_stpcpy", "_stpncpy", "_strcasecmp",
    "_strcasestr", "_strcat", "_strcmp", "_strcspn", "_strdup", "_strlcat",
    "_strlcpy", "_strncasecmp", "_strncat", "_strncmp", "_strncpy",
    "_strndup", "_strpbrk", "_strrchr", "_strsep", "_strspn", "_strstr",
    "_strtok", "_strtok_r",
]

tbd = SDK / "usr/lib/libSystem.B.tbd"
text = tbd.read_text()
if "_strcmp," in text or "_strcmp ]" in text:
    print("libSystem.B.tbd: already patched")
else:
    block = ("  - archs:             [ armv7, armv7s, arm64 ]\n"
             "    symbols:           [ " + ", ".join(SYMBOLS) + " ]\n")
    lines = text.splitlines(keepends=True)
    end = max(i for i, l in enumerate(lines) if l.strip() == "...")
    lines.insert(end, block)
    tbd.write_text("".join(lines))
    print(f"libSystem.B.tbd: appended {len(SYMBOLS)} libc symbols")

launch = SDK / "usr/lib/system/liblaunch.tbd"
src = pathlib.Path(__file__).parent / "liblaunch.tbd"
if launch.exists():
    print("liblaunch.tbd: already installed")
else:
    launch.write_text(src.read_text())
    print("liblaunch.tbd: installed")
