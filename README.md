# iPhone 4S Survival GPS — project master reference

A jailbroken, activation-locked iPhone 4S (iOS 8.4.1, armv7) rebuilt into a
fully **offline** survival instrument: GPS, offline topo map, sensors, and —
the hard-won part — it **boots with no network at all**.

Everything here is rebuildable from this folder plus the two big regenerables
(the toolchain and the map tiles). If we ever lose the thread, start here.

---

## 1. What exists

Four bare-text apps on the phone (green-on-black, one job each):

| App | Dir | What it does |
|-----|-----|--------------|
| **Track Bag** | `app/` | Navigator: position (decimal/DMS/MGRS), compass rose + dart to a target, MARK + PINS |
| **GPS Bag** | `rawapp/` | Pure position + compass readout, zero interaction |
| **Device Bag** | `deviceapp/` | Sensors: compass, motion/tilt, light, board temps, battery internals, RAM/disk/uptime |
| **Map Bag** | `mapapp/` | Offline USGS topo map (4.56 GB of tiles on the phone), waypoint pins, long-press/ENTER to add pins |

Shared code: `shared/Geo.c` (MGRS/DMS/UTM/bearings, verified against NGA
GEOTRANS; test suite in `app/test/geo_test.c` gates every build).

**The offline-boot fix** lives in `actfix/` — see section 4. This is the thing
that makes the whole project actually usable in the field.

---

## 2. How it's built (no Xcode, no WSL)

Windows PC can't link armv7 Mach-O, so a **2015 MacBook Pro is the build
server** over SSH. Flow: source on the PC → `deploy.py` copies it to the Mac
→ Apple clang + real `ld64` build armv7/iOS 8 → bundle relayed back → pushed
to the phone → `ldid` pseudo-signs on the phone → `uicache`.

- Toolchain (Windows side): `toolchain/` — clang + inspection tools + the iOS
  9.3 SDK, all rebuildable by `tools/setup_toolchain.py`. (Now mostly a relic;
  the Mac does the real work. LLD can't link armv7 — that's why the Mac matters.)
- The Mac's SDK must be completed by `tools/patch_sdk.py` (adds the liblaunch
  stub + libc symbols the community SDK omits) or links fail on `_memcpy`/`_strcmp`.

### Deploy an app
```
python tools/deploy.py trackbag     # or: mapbag | gpsbag | devicebag
```
Builds (tests must pass), installs over SSH, resprings. ~15 s.

---

## 3. Getting into the phone (READ THIS — it wasted hours)

- **SSH is over Wi‑Fi only.** Host alias `iphone` = `root@192.168.50.140`,
  config in `ssh_config` (has the required `HostKeyAlgorithms +ssh-rsa`).
  `ssh -F ssh_config iphone`.
- **USB port 22 is ALWAYS refused** — the phone's sshd binds the Wi‑Fi
  interface, not loopback. Don't chase it.
- **The phone's Wi‑Fi sleeps when the screen locks** → SSH just times out.
  Keep it **unlocked and awake** (Auto‑Lock → Never) while working, or you'll
  think it's dead when it isn't.
- **USB tools** (in `<scratchpad>/imd/`, bundled libimobiledevice, no iTunes
  needed): `idevice_id -l`, `ideviceinfo -k ActivationState`,
  `ideviceactivation`, `iproxy`. These work over the cable even at the
  activation screen (usbmux/lockdown services) — but **SSH is not one of them**.
- A reboot drops the USB "Trust" — re-tap **Trust** on the phone (or
  `idevicepair pair`).
- Keys were generated fresh (`~/.ssh/iphone4s_ed25519`). If access is lost,
  re-add the pubkey to the phone (and Mac) with the one-liner in memory.

---

## 4. The offline-activation fix (the big one)

**Problem:** the phone demanded activation on **every boot**, and activation
needed Wi‑Fi — so with no network it was stuck forever on "Activation
Required." Useless as a field device.

**It was NOT iCloud lock** (`mobactivationd` logs `NOT enrolled in FMiP`). It
was ordinary **cellular** activation: the baseband made the daemon fetch an
activation ticket from `albert.apple.com` each boot. Wi‑Fi‑only devices skip
this by reading MobileGestalt **`ShouldHactivate` = true** and
"short‑circuiting activation to Activated" locally.

**Fix:** a tiny shim (`actfix/hook_mg.c` + fishhook) injected into **only**
`mobactivationd` via `DYLD_INSERT_LIBRARIES` in its launch plist. It forces
`MGCopyAnswer("ShouldHactivate")` → true. The daemon then logs
`Short circuiting activation state to Activated` — offline, no server. Nothing
else on the device is affected.

On the phone:
- `/usr/lib/actfix_mg.dylib` — the shim
- `/Library/LaunchDaemons/com.apple.mobileactivationd-iphoneos.plist` — has the
  added `DYLD_INSERT_LIBRARIES` line (source: `actfix/mad_hook.plist`)
- `/var/root/mad_orig.plist` — backup of the original config

Full detail + rebuild command: [actfix/README.md](actfix/README.md).

### Revert to stock (if ever needed)
```
cp /var/root/mad_orig.plist /Library/LaunchDaemons/com.apple.mobileactivationd-iphoneos.plist
rm /usr/lib/actfix_mg.dylib
reboot            # then activate once over Wi‑Fi to get back to the home screen
```

---

## 5. The offline map

- `tools/harvest_tiles.py` — resumable, polite harvester of USGS "The National
  Map" topo tiles into an MBTiles (SQLite) file. Three tiers: CONUS z0‑11,
  Southeast z12‑13, Alabama+buffer z14. ~205k tiles / 4.4 GB.
- `tools/pack_tiles.py` — repacks to non‑WAL journal mode (iOS 8's SQLite can't
  open WAL read‑only) before pushing.
- On the phone: `/var/mobile/Media/MapBag/tiles.mbtiles`. Map Bag serves it via
  `MKTileOverlay` with `canReplaceMapContent` + overzoom to z22 so Apple's
  online tiles can never leak in.
- **Keep a backup of `tiles/usgs_topo.mbtiles`** (the ~4.4 GB master) somewhere
  safe — it's gitignored and a re-harvest is ~1 hour.

---

## 6. Where the backups are

- Original activation config: on phone at `/var/root/mad_orig.plist`
- Full activation baseline (Lockdown state, daemon, records):
  `<scratchpad>/backup_activation/act_baseline.tgz`
- Waypoints/status the apps share: `/var/mobile/Library/GPSBag/`
- The master tile file: `tiles/usgs_topo.mbtiles` (keep an external copy)

---

## 7. Directory layout

```
app/        Track Bag (navigator)      + test/ geodesy tests
rawapp/     GPS Bag (raw readout)
deviceapp/  Device Bag (sensors)       + probe/ (PrivateSensors probe)
mapapp/     Map Bag (offline map)
shared/     Geo.c/.h (shared geodesy)
actfix/     >>> the offline-activation fix + its README <<<
tools/      setup_toolchain, patch_sdk, harvest_tiles, pack_tiles,
            make_icons, deploy.py
toolchain/  Windows clang + iOS SDK (regenerable; gitignored)
tiles/      map tile master (gitignored)
ssh_config  host aliases: iphone, mac
```

---

## 8. Security note

When done working, SSH keys can be revoked again (phone `authorized_keys` +
the local keypair) — just ask. Keep the phone's Wi‑Fi **off** in the bag: GPS
doesn't need it, and an unreachable radio is the only perfect firewall.

---

*One phone Apple wrote off, rebuilt from a Windows PC, a junk MacBook, and SSH.
It powers on and works with zero connectivity. That was the whole point.*
