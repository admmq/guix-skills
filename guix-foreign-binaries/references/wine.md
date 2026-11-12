# Windows programs with Wine on Guix

## Pick the right Wine package

| Package | What it is | Use for |
|---|---|---|
| `wine` | 32-bit only (built for i686) | Rarely the right choice on x86_64 |
| `wine64` | WoW64 build: runs 64-bit **and** 32-bit programs | Default choice |
| `winetricks` | Installs runtimes (d3dx9, vcrun, xact, DXVK…) | Optional extras |

- Keep **only one** in the profile, since both provide `wine`. Switch with `guix remove wine && guix install wine64 && hash -r`.
- A prefix records its architecture when it's created. A 64-bit prefix driven by 32-bit-only `wine` fails, for example with `wine: failed to open "C:\windows\regedit.exe"`. Use a fresh prefix after switching.

## Prefix per program

```sh
export WINEPREFIX="$HOME/.wine-<app>"      # never nest inside ~/.wine (that's a prefix too)
wineboot -u                                # create/update
winetricks -q d3dx9 vcrun2010              # only what the program needs
wine /path/to/setup.exe
```
Uninstall the whole thing with `rm -rf "$WINEPREFIX"`.

## Installers

GOG, Steam-style and other offline installers often come as one `.exe` plus `-1.bin`, `-2.bin` and so on. Check that **all** parts are present and correctly named. Browsers rename duplicate downloads, for example to `file(1).bin`. A missing part makes the install fail partway through.

## Diagnosing winetricks failures

- Read the log for the **first** real error. A `cabextract` "extra bytes at end of file" warning and the "winetricks is outdated" notice are harmless.
- A verb can partly succeed. For example, the 32-bit `regedit` step applies the DLL overrides, and the 64-bit one fails afterwards. Check what actually landed before redoing anything:
  - DLLs in `drive_c/windows/syswow64` (32-bit) and `drive_c/windows/system32` (64-bit)
  - overrides in `$WINEPREFIX/user.reg` (`"*d3dx9_43"="native"`)
- Some Guix `wine64` builds can't start **64-bit built-ins by their full `C:\windows\…` path** ("cannot find builtin library"), while `wine regedit` (by name) and 32-bit programs from `syswow64` work. Test both forms before blaming the setup. For 32-bit games, the 64-bit half usually doesn't matter.

## Graphics and performance

- Check that GL and Vulkan work on the host first (`glxinfo`, `vulkaninfo` via `guix shell mesa-utils vulkan-tools`).
- DXVK (through winetricks) helps with D3D9, D3D10 and D3D11 games.

## Gamepads (for example a DualSense or DualShock)

1. System config: add `(service bluetooth-service-type)` for Bluetooth controllers, and `(udev-rules-service 'steam-devices steam-devices-udev-rules)` so the user can open `/dev/hidraw*`. Then reconfigure and reboot.
2. Pair with `bluetoothctl` (in `bluez`). Put the controller in pairing mode, then `scan on`, `pair`, `trust`, `connect`.
3. Check that Linux sees it: look in `/proc/bus/input/devices`, and confirm `/dev/hidraw*` is accessible to the user.
4. Check that Wine sees it: `wine control` → Game Controllers. Guix's Wine is built with SDL2.
5. If a game ignores it, make Wine present it as an XInput (Xbox-style) pad by disabling hidraw for that device under `HKLM\System\CurrentControlSet\Services\winebus` (`DisableHidraw`=1). Undo by deleting the value.
