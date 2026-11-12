---
name: guix-desktop-troubleshooting
description: Diagnose desktop, hardware and networking problems specific to Guix System, such as blank icons in Qt apps, missing hardware video decoding, gamepads and udev permissions, Bluetooth, screen flicker on Intel laptops, admin tools like nft or iptables missing, NetworkManager connection sharing or hotspots with a VPN, and apps opening in the wrong session under nested compositors. Use when a desktop app or device misbehaves on Guix System and the cause may be Guix's non-FHS layout, missing services, or environment variables.
---

# Desktop and hardware troubleshooting on Guix System

Related skills: `guix-host-environment`, `guix-system-configuration`, `guix-foreign-binaries` (Wine, gamepads in games).

Most of these are leads to verify on the machine, not guaranteed fixes. Test, then report what was confirmed.

## Icons missing in Qt apps

- Qt apps ask the desktop icon theme for standard names such as `media-playback-start`. Qt chooses the theme from the detected desktop (`XDG_CURRENT_DESKTOP`). Under an unrecognized window manager it may fall back to `hicolor`, which has none of those icons, so buttons come out blank in every Qt app of the session.
- To check: confirm the icons exist (`find /run/current-system/profile/share/icons ~/.guix-profile/share/icons -name 'media-playback-start*'`). Adwaita's standard icons can be in `AdwaitaLegacy`. Then test with a known desktop value, or a Qt platform theme (`QT_QPA_PLATFORMTHEME`, for example via qt5ct/qt6ct).
- Robust fix in your own app: bundle icons as resources instead of relying on the theme.
- SVG icons, including window icons, need `qtsvg` in the package inputs.

## Video playback is slow (no hardware decoding)

- Intel: install `intel-media-driver` and set `LIBVA_DRIVER_NAME=iHD` and `LIBVA_DRIVERS_PATH=<profile>/lib/dri`. Check with `vainfo` from `libva-utils`.
- Players must be built with VA-API or Vulkan decode support. Check the player's own diagnostic output.

## Gamepads, raw HID, Bluetooth

- `/dev/hidraw*` is root-only by default. Add `(udev-rules-service 'steam-devices steam-devices-udev-rules)` to the system services.
- Bluetooth needs `(service bluetooth-service-type)`. `bluetoothctl` comes from `bluez`.

## Screen flicker on Intel laptops

- Panel Self Refresh (PSR) can cause flicker, for example when opening the lid. Test with the kernel argument `i915.enable_psr=0` (`(kernel-arguments (append '("i915.enable_psr=0") %default-kernel-arguments))`). Keep it only if it helps.

## Admin tools aren't installed

- Guix System may have no firewall service at all, and `nft`, `iptables`, `dnsmasq` and `tcpdump` aren't on `PATH`. Run them via `guix shell`, and under sudo with the store path: `sudo "$(guix shell nftables -- sh -c 'command -v nft')" list ruleset`.
- The system log is `/var/log/messages` (root). Service status: `sudo herd status <svc>`.

## Sharing a connection or VPN with NetworkManager

- `nmcli connection up` works for users in `netdev`. `add`, `modify` and `delete` of system connections need sudo.
- Shared mode (`ipv4.method shared`) runs dnsmasq for DHCP and DNS and sets up NAT. Recent NetworkManager versions reject `ipv4.dns` on shared connections. Put dnsmasq options in a file under `/etc/NetworkManager/dnsmasq-shared.d/` instead.
- If clients get an address but no internet through a VPN interface that NetworkManager doesn't manage, forwarding is only enabled on managed interfaces. Enable it on the VPN interface (`sysctl -w net.ipv4.conf.<vpn-if>.forwarding=1`). It resets whenever the VPN reconnects.
- Wi-Fi access point limits: many cards can't host an AP on 5 GHz (no-IR channels), and AP plus client on one card must share a channel. `iw list` shows the supported interface combinations. For a USB dongle, bind the profile to its permanent MAC (`802-11-wireless.mac-address`), not its interface name, because the name changes with the port.

## Apps open in the wrong session when testing a nested compositor

- Single-instance apps (Chromium-based browsers, Firefox) hand the request to an already-running instance on the other display and exit. Start them with a separate profile (`--user-data-dir=…`, or `firefox --new-instance -P <profile>`).
- Global shortcuts such as Super+number may be grabbed by the outer desktop. Test with other bindings, or in a separate VT session.
