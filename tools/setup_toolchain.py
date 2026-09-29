"""Set up the Windows-native iOS 8 / armv7 cross toolchain inside ./toolchain.

Nothing is installed system-wide; deleting ./toolchain undoes everything.

  toolchain/llvm/                 clang + inspection tools (LLVM release)
  toolchain/sdks/iPhoneOS9.3.sdk  iOS SDK headers and .tbd stubs (theos/sdks)

Safe to re-run: finished steps are skipped.
"""
import pathlib
import shutil
import subprocess
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
TOOLCHAIN = ROOT / "toolchain"

LLVM_VERSION = "23.1.2"
LLVM_NAME = f"clang+llvm-{LLVM_VERSION}-x86_64-pc-windows-msvc"
LLVM_URL = (f"https://github.com/llvm/llvm-project/releases/download/"
            f"llvmorg-{LLVM_VERSION}/{LLVM_NAME.replace('+', '%2B')}.tar.xz")
LLVM_DIR = TOOLCHAIN / "llvm"
# Only what the build needs: the compiler, clang's own headers, and tools for
# inspecting the output. LLD is deliberately absent: ld64.lld has no armv7
# support (its partial ARM32 port was removed after LLVM 16, and even that
# could not read armv7 scattered relocations).
LLVM_MEMBERS = [f"{LLVM_NAME}/bin/{exe}.exe" for exe in (
    "clang", "llvm-lipo", "llvm-nm", "llvm-objdump", "llvm-otool",
    "llvm-size", "llvm-strip")] + [f"{LLVM_NAME}/lib/clang"]

SDK_REPO = "https://github.com/theos/sdks.git"
SDK_NAME = "iPhoneOS9.3.sdk"
SDK_CHECKOUT = TOOLCHAIN / "sdks"


def run(*args, **kw):
    print("+", " ".join(str(a) for a in args))
    return subprocess.run(args, check=True, **kw)


def setup_llvm():
    if (LLVM_DIR / "bin" / "clang.exe").exists():
        print("llvm: present")
        return
    archive = TOOLCHAIN / "llvm.tar.xz"
    if not archive.exists():
        print(f"llvm: downloading {LLVM_URL}")
        tmp = archive.with_suffix(".part")
        urllib.request.urlretrieve(LLVM_URL, tmp)
        tmp.rename(archive)
    LLVM_DIR.mkdir(parents=True, exist_ok=True)
    run("tar", "-xf", archive, "-C", LLVM_DIR, "--strip-components=1", *LLVM_MEMBERS)
    archive.unlink()


def materialize_symlinks(checkout: pathlib.Path, prefix: str):
    """Replace git's symlink placeholders with real copies of their targets.

    Without Windows symlink privileges, git checks symlinks out as small text
    files holding the target path, which clang and lld would read as garbage.
    """
    def git(*args):
        return subprocess.run(["git", "-C", checkout, *args], check=True,
                              capture_output=True).stdout

    # path -> link target text, as recorded by git
    links = {}
    for line in git("ls-files", "-s", prefix).decode().splitlines():
        meta, rel = line.split("\t", 1)
        mode, sha, _ = meta.split()
        if mode == "120000":
            links[(checkout / rel).resolve()] = git("cat-file", "-p", sha)

    def is_placeholder(path):
        return path.is_file() and path.read_bytes() == links[path]

    pending = [p for p in links if is_placeholder(p)]
    # A link may point at another link; copy a target only once it is real.
    while pending:
        unresolved = []
        for link in pending:
            target = (link.parent / links[link].decode()).resolve()
            if target in links and is_placeholder(target):
                unresolved.append(link)
                continue
            link.unlink()
            if target.is_dir():
                shutil.copytree(target, link)
            else:
                shutil.copy2(target, link)
        if len(unresolved) == len(pending):
            sys.exit(f"sdk: unresolvable symlinks: {unresolved}")
        pending = unresolved
    print(f"sdk: {len(links)} symlinks materialized")


def setup_sdk():
    if not (SDK_CHECKOUT / ".git").exists():
        # autocrlf off: .tbd stubs are recognized by their exact "---\narchs:"
        # header, so CRLF line endings make linkers reject them.
        no_convert = ["-c", "core.symlinks=false", "-c", "core.autocrlf=false"]
        run("git", *no_convert, "clone", "-q", "--depth", "1",
            "--filter=blob:none", "--sparse", SDK_REPO, SDK_CHECKOUT)
        run("git", "-C", SDK_CHECKOUT, "config", "core.symlinks", "false")
        run("git", "-C", SDK_CHECKOUT, "config", "core.autocrlf", "false")
        run("git", "-C", SDK_CHECKOUT, "sparse-checkout", "set", SDK_NAME)
    materialize_symlinks(SDK_CHECKOUT, SDK_NAME)


if __name__ == "__main__":
    TOOLCHAIN.mkdir(exist_ok=True)
    setup_llvm()
    setup_sdk()
    print("toolchain ready")
