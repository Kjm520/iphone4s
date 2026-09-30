# Offline activation fix (the "activation required on every boot" cure)

## The problem
The 4S is **not** iCloud/Activation-Lock locked (`mobactivationd` logs
`NOT enrolled in FMiP`). What blocked offline use was **ordinary cellular
activation**: every boot, `mobactivationd` saw `HasBaseband = true`, set
`should_hactivate = false`, and insisted on fetching a **baseband
activation ticket from albert.apple.com** — which needs Wi-Fi. No network =
stuck on "Activation Required" forever.

Wi-Fi-only devices (iPod touch, Wi-Fi iPad) never do this: the daemon reads
MobileGestalt **`ShouldHactivate`**, gets `true`, and **short-circuits
activation to Activated** locally, no server. The fix simply makes this
baseband device take that same built-in path.

## The fix
A tiny library injected into **only** `mobactivationd` that forces the one
MobileGestalt answer `ShouldHactivate` to `true` (via fishhook). Everything
else on the device is untouched.

Result in the daemon log:
```
has_telephony: true, should_hactivate: true
dealwith_activation: Short circuiting activation state to Activated.
```

### Files installed on the phone
- `/usr/lib/actfix_mg.dylib` — the shim (built from `hook_mg.c` + `fishhook.c`)
- `/Library/LaunchDaemons/com.apple.mobileactivationd-iphoneos.plist` — the
  daemon's launch config, with a `DYLD_INSERT_LIBRARIES` entry pointing at the
  shim (see `mad_hook.plist` for the exact contents)
- Original launch config backed up on-device at `/var/root/mad_orig.plist`

### Source
- `hook_mg.c` — the shim (fishhook rebind of `MGCopyAnswer`)
- `fishhook.c/.h` — Facebook fishhook (BSD), symbol rebinding
- `mad_hook.plist` — the modified daemon plist (adds the DYLD_INSERT line)
- `mg_probe.c` / `mg_probe2.c` — read-only MobileGestalt probes used to find
  the `ShouldHactivate` lever

## Rebuild + reinstall (on the Mac build server, then push over SSH)
```
clang -dynamiclib -target armv7-apple-ios8.0 -isysroot ~/ios/sdks/iPhoneOS9.3.sdk \
    -install_name /usr/lib/actfix_mg.dylib -framework CoreFoundation \
    hook_mg.c fishhook.c -o actfix_mg.dylib
# push actfix_mg.dylib -> /usr/lib/ ; ldid -S it ; chmod 755
# push mad_hook.plist -> /Library/LaunchDaemons/com.apple.mobileactivationd-iphoneos.plist
```
(The SDK must be patched first — see `tools/patch_sdk.py` — or the link fails
on missing libc symbols.)

## Revert (back to stock, needs Wi-Fi to reactivate afterward)
```
cp /var/root/mad_orig.plist \
   /Library/LaunchDaemons/com.apple.mobileactivationd-iphoneos.plist
rm /usr/lib/actfix_mg.dylib
reboot   # then activate once over Wi-Fi
```

## Test method that made this safe
The whole thing was proven **without risking a bad boot**: `mobactivationd`
is a launchd daemon, so the shim was first loaded in-memory by reloading the
daemon from a `/tmp` copy of the plist (`launchctl unload/load/start`) and
reading its log — the on-disk system files were never touched until the fix
was confirmed. Only then was it persisted and boot-tested with Airplane Mode.
