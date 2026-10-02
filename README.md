# iPhone 4S Survival GPS - project overview

A jailbroken, activation-locked iPhone 4S (iOS 8.4.1, armv7, IMEI 9900\*) rebuilt into a
fully **offline** survival instrument: GPS, offline topo map, sensors, and -
most importantly - **it works with the activation lock bug**.

Requirements: LLVM, iPhoneOS 9.3 SDK, SSH for iPhone, SSH or physical access to a Mac, Legacy iOS Kit, Claude or equivalent for the LLVM and thumb-2

<br>

## 1. The Problem:

### Objective

Make use of this old device's GPS functionality with offline maps so it can go in my emergency survival bag and will be useable without any network connection.

TLDR: 8.4.1 is the last version that can activate on the 9900\*s, but it can only be done with network connection, on every launch. Meaning that when fully offline, the device cannot activate on a fresh boot.

- Search for existing apps, all are incompatible →
- update iOS from 9.3.5 to the last 9.3.6 to retry, permanently locked out by activation lock bug →
- downgrade to 8.4.1 to login there, downgrade requires jailbreak, Cydia requires phone access, phone inaccessible via activation lock loop →
- try various methods like [timed SIM card removal](https://github.com/LukeZGD/Legacy-iOS-Kit/discussions/1092) to allow enough time before getting locked out, doesn't work →
- use Legacy iOS Kit to "attempt activation" with ideviceactivation, CLI says success but device lock loop immediately revokes it →
- attempt Legacy iOS Kit's activation stitching, requires pwnDFU, requires RP2040, requires [check-m8 A5](https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/checkm8-a5)
- flash checkm8-a5 8940 A5 U2F to RP2040, pwnDFU, downgrade to non-jailbroken 8.4.1, attempt native activation, this time get a new rejection message along the lines of "try again later" or "try iTunes" →
- wait 5 mins, try again using wifi, when asked to login "skip this step", and then get access to the homescreen without the loop bug locking me out again →
- return to Legacy iOS Kit to save these activation records for stitching, pwnDFU again, save records, reboot phone, "skip" activation again →
- attempt Apple's native update path to iOS 9 since we are now doing so from an activated state hoping the device will preserve it, it does not →
- pwnDFU again, make sure activation records tar is in Legacy iOS Kit's folder, CLI should confirm "Existing activation records detected. Activation Records stitching enabled."
- attempt restore using DRA v6 base iOS 6.1.3 with target 9.2.1 and stitching records then attempt native 9.2 to 9.3 →
- 9.2.1 won't activate with the "try again later" rejection again, wait and retry like last time, but this time it will not allow activation →
- conclusion: unable to get back to a native 9.3 activated state, and jailbreaking 9.3 to try to fix the activation lock is excessive, settle for jailbreaking iOS 8 since it naturally can activate →
- now attempt Apple login on an activated jailbroken iOS 8, trigger 2FA code elsewhere, append to password, it fails
- at this point I go to Apple and leave feedback that it's not cool that the activation loop prevents any phone use and they have not provided any authentication method or end-of-support mechanism that would allow people to continue using the device that they own →
- Using Cydia, install OpenSSH, **NOW, this project directory is created to finally begin the actual GPS app work.** →
- create and implement bare apps →
- trial run, boot and launch during test drive in a new location, fails because cannot activate period (not the loop bug) because no network connection →
- the activation problem is still not beaten. Even once activated, every cold boot re-runs activation, and activation wants network. so offline = stuck on "Activation Required" forever.

<br>

## 2. The Fix: offline activation

TLDR: a cellular 4S phones apple for a baseband activation ticket on every boot; wifi-only devices (ipod touch, wifi ipad) skip that and self-activate locally. make the 4S take the wifi-only path and it boots offline.

- first rule out the nightmare one: is this iCloud / Find-My (FMiP) lock? no → mobactivationd logs `NOT enrolled in FMiP`. it's plain **cellular** activation, which is a software decision, not a server-side ownership lock →
- watch mobactivationd on boot: sees `HasBaseband=true` → sets `should_hactivate=false` → calls out to `albert.apple.com` for a baseband ticket. no network, no ticket, no homescreen →
- the wifi-only path instead reads a MobileGestalt flag `ShouldHactivate=true` and logs `Short circuiting activation state to Activated` locally, no server. that's the path we want →
- how does the daemon actually decide? disassemble the relevant stretch of mobactivationd (thumb-2, armv7 - snippet saved in Thumb.txt) to see which gestalt keys drive it, then hook `MGCopyAnswer` to LOG every key it reads on boot: HasBaseband, ShouldHactivate, DeviceClass, ProductType... →
- try faking DeviceClass / ProductType to look like a non-phone → does NOT flip has_telephony, daemon still demands the ticket →
- try forcing just `ShouldHactivate` → true → daemon logs `Short circuiting activation state to Activated`. single lever found →
- build a tiny dylib (`actfix/hook_mg.c`) that fishhook-rebinds `MGCopyAnswer`: if the key is "ShouldHactivate" return true, otherwise call through to the real one. scope it to ONLY mobactivationd via a `DYLD_INSERT_LIBRARIES` line in that one daemon's launchd plist - nothing else on the device is touched →
- don't gamble on a bad boot: prove the shim live first. copy the plist to /tmp, `launchctl unload/load/start` the daemon from there, read its log. system files stay untouched until it's confirmed. (also drop a /tmp marker in the dylib's constructor to confirm DYLD_INSERT is even honored for this daemon - it is) →
- build on the mac: `clang -dynamiclib -target armv7-apple-ios8.0 -isysroot <9.3 sdk> -framework CoreFoundation hook_mg.c fishhook.c -o actfix_mg.dylib` → push to /usr/lib, `ldid -S`, chmod 755 → back up the original plist to /var/root/mad_orig.plist first → drop in the modified plist →
- reboot in Airplane Mode → boots straight to the homescreen, no network, no activation screen. that was the whole point →
- fully reversible: restore mad_orig.plist, `rm` the dylib, reboot, reactivate once over wifi and you're back to stock.

<br><br>

<hr style="height: 5px; border: none; background-color: #4c00ff;" />
<br><br>

# iPhone 4S Survival GPS - the apps

## 1. What exists

Four bare-text apps on the phone (green-on-black, one job each):

| App            | Dir          | What it does                                                                                       |
| -------------- | ------------ | -------------------------------------------------------------------------------------------------- |
| **Track Bag**  | `app/`       | Navigator: position (decimal/DMS/MGRS), compass rose + dart to a target, MARK + PINS               |
| **GPS Bag**    | `rawapp/`    | Pure position + compass readout, zero interaction                                                  |
| **Device Bag** | `deviceapp/` | Sensors: compass, motion/tilt, light, board temps, battery internals, RAM/disk/uptime              |
| **Map Bag**    | `mapapp/`    | Offline USGS topo map (4.56 GB of tiles on the phone), waypoint pins, long-press/ENTER to add pins |

Shared code: `shared/Geo.c` (MGRS/DMS/UTM/bearings, verified against NGA
GEOTRANS; test suite in `app/test/geo_test.c` gates every build).

**The offline-boot fix** lives in `actfix/` - see section 4. This is the thing
that makes the whole project actually usable in the field.

<br><br>

## 2. How it's built (no Xcode, no WSL)

Windows PC can't link armv7 Mach-O, so a **2015 MacBook Pro is the build
server** over SSH. Flow: source on the PC → `deploy.py` copies it to the Mac
→ Apple clang + real `ld64` build armv7/iOS 8 → bundle relayed back → pushed
to the phone → `ldid` pseudo-signs on the phone → `uicache`.

- Toolchain (Windows side): `toolchain/` - clang + inspection tools + the iOS
  9.3 SDK, all rebuildable by `tools/setup_toolchain.py`. (Now mostly a relic;
  the Mac does the real work. LLD can't link armv7 - that's why the Mac matters.)
- The Mac's SDK must be completed by `tools/patch_sdk.py` (adds the liblaunch
  stub + libc symbols the community SDK omits) or links fail on `_memcpy`/`_strcmp`.

### Deploy an app

```
python tools/deploy.py trackbag     # or: mapbag | gpsbag | devicebag
```

Builds (tests must pass), installs over SSH, resprings. ~15 s.

<br><br>

## 3. Getting into the phone (READ THIS - it wasted hours)

- **SSH is over Wi-Fi only.** Host alias `iphone` = `root@<phone-lan-ip>`,
  config in `ssh_config` (has the required `HostKeyAlgorithms +ssh-rsa`).
  `ssh -F ssh_config iphone`.
- **USB port 22 is ALWAYS refused** - the phone's sshd binds the Wi-Fi
  interface, not loopback. Don't chase it.
- **The phone's Wi-Fi sleeps when the screen locks** → SSH just times out.
  Keep it **unlocked and awake** (Auto-Lock → Never) while working, or you'll
  think it's dead when it isn't.
- **USB tools** (in `<scratchpad>/imd/`, bundled libimobiledevice, no iTunes
  needed): `idevice_id -l`, `ideviceinfo -k ActivationState`,
  `ideviceactivation`, `iproxy`. These work over the cable even at the
  activation screen (usbmux/lockdown services) - but **SSH is not one of them**.
- A reboot drops the USB "Trust" - re-tap **Trust** on the phone (or
  `idevicepair pair`).
- Keys were generated fresh (`~/.ssh/iphone4s_ed25519`). If access is lost,
  re-add the pubkey to the phone (and Mac) with the one-liner in memory.

<br><br>

## 4. The offline-activation fix (the big one)

**Problem:** the phone demanded activation on **every boot**, and activation
needed Wi-Fi - so with no network it was stuck forever on "Activation
Required." Useless as a field device.

**It was NOT iCloud lock** (`mobactivationd` logs `NOT enrolled in FMiP`). It
was ordinary **cellular** activation: the baseband made the daemon fetch an
activation ticket from `albert.apple.com` each boot. Wi-Fi-only devices skip
this by reading MobileGestalt **`ShouldHactivate` = true** and
"short-circuiting activation to Activated" locally.

**Fix:** a tiny shim (`actfix/hook_mg.c` + fishhook) injected into **only**
`mobactivationd` via `DYLD_INSERT_LIBRARIES` in its launch plist. It forces
`MGCopyAnswer("ShouldHactivate")` → true. The daemon then logs
`Short circuiting activation state to Activated` - offline, no server. Nothing
else on the device is affected.

On the phone:

- `/usr/lib/actfix_mg.dylib` - the shim
- `/Library/LaunchDaemons/com.apple.mobileactivationd-iphoneos.plist` - has the
  added `DYLD_INSERT_LIBRARIES` line (source: `actfix/mad_hook.plist`)
- `/var/root/mad_orig.plist` - backup of the original config

Full detail + rebuild command: [README_activation_fix.md](README_activation_fix.md).

### Revert to stock (if ever needed)

```
cp /var/root/mad_orig.plist /Library/LaunchDaemons/com.apple.mobileactivationd-iphoneos.plist
rm /usr/lib/actfix_mg.dylib
reboot            # then activate once over Wi-Fi to get back to the home screen
```

<br><br>

## 5. The offline map

- `tools/harvest_tiles.py` - resumable, polite harvester of USGS "The National
  Map" topo tiles into an MBTiles (SQLite) file. Three tiers: CONUS z0-11,
  Southeast z12-13, Alabama+buffer z14. ~205k tiles / 4.4 GB.
- `tools/pack_tiles.py` - repacks to non-WAL journal mode (iOS 8's SQLite can't
  open WAL read-only) before pushing.
- On the phone: `/var/mobile/Media/MapBag/tiles.mbtiles`. Map Bag serves it via
  `MKTileOverlay` with `canReplaceMapContent` + overzoom to z22 so Apple's
  online tiles can never leak in.
- **Keep a backup of `tiles/usgs_topo.mbtiles`** (the ~4.4 GB master) somewhere
  safe - it's gitignored and a re-harvest is ~1 hour.

<br><br>

## 6. Where the backups are

- Original activation config: on phone at `/var/root/mad_orig.plist`
- Full activation baseline (Lockdown state, daemon, records):
  `<scratchpad>/backup_activation/act_baseline.tgz`
- Waypoints/status the apps share: `/var/mobile/Library/GPSBag/`
- The master tile file: `tiles/usgs_topo.mbtiles` (keep an external copy)

<br><br>

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

<br><br>

## 8. Security note

When done working, SSH keys can be revoked again (phone `authorized_keys` +
the local keypair) - just ask. Keep the phone's Wi-Fi **off** in the bag: GPS
doesn't need it, and an unreachable radio is the only perfect firewall.

_One phone Apple wrote off, rebuilt from a Windows PC, a junk MacBook, and SSH.
It powers on and works with zero connectivity. That was the whole point._
