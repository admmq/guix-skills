---
name: guix-system-configuration
description: Write, review and apply Guix System operating-system configurations, covering users and groups, file systems and LUKS, swap, bootloader, kernel and firmware, initrd modules, services (adding, extending, modifying), substitute servers, installer and VM images, and the build → reconfigure → roll-back workflow. Use when editing or reviewing a system config .scm, when guix system reconfigure fails, when adding hardware support (Bluetooth, gamepads, udev rules, setuid helpers), or when building an ISO or VM image.
---

# Guix System configuration

Related skills: `guix-services` (writing new service types), `guix-channels` (channel errors during reconfigure), `guix-home` (per-user config), `guix-desktop-troubleshooting`.

## Workflow

1. **Find the real config file.** It's often in a repo, not `/etc/config.scm`. `guix system describe` shows a store copy of the config the running system was built from.
2. **Edit**, keeping the existing style (prefixed imports, shared variables from a channel).
3. **Build without activating:** `guix system build [-L <channel-dir>] config.scm`. This evaluates everything and builds the system, but changes nothing.
4. **Apply** (ask first, since it needs sudo): `sudo guix system reconfigure config.scm`. The usual sequence is `guix pull`, then `sudo guix system reconfigure …`.
5. **Reboot** if the kernel, initrd, bootloader or core services changed. Otherwise services restart on demand, or with `sudo herd restart <svc>`.
6. **Undo:** `sudo guix system roll-back`, or pick an older generation in the boot menu. `guix system list-generations` lists them.

Other targets: `guix system vm config.scm` (a throwaway QEMU VM), `guix system image --image-type=iso9660 config.scm`, and `guix system container`.

## Skeleton

```scheme
(use-modules (gnu) (gnu system nss)
             ((my-channel packages foo) #:prefix my:))
(use-service-modules desktop networking ssh xorg)
(use-package-modules bootloaders certs linux)

(operating-system
  (host-name "host")
  (timezone "Europe/Berlin")
  (locale "en_US.utf8")
  (bootloader (bootloader-configuration
               (bootloader grub-efi-bootloader)
               (targets '("/boot/efi"))))
  (mapped-devices
   (list (mapped-device
          (source (uuid "<luks-uuid>"))
          (target "cryptroot")
          (type luks-device-mapping))))
  (file-systems (append
                 (list (file-system
                         (device (file-system-label "ROOT"))
                         (mount-point "/")
                         (type "ext4")
                         (dependencies mapped-devices))   ; root is inside LUKS
                       (file-system
                         (device (file-system-label "BOOT"))
                         (mount-point "/boot/efi")
                         (type "vfat")))
                 %base-file-systems))
  (swap-devices (list (swap-space (target "/swapfile"))))
  (users (cons* (user-account
                 (name "alice")
                 (group "users")
                 (supplementary-groups '("wheel" "netdev" "audio" "video")))
                %base-user-accounts))
  (packages (append (list my:foo) %base-packages))
  (services (append (list (service bluetooth-service-type))
                    %desktop-services))
  (name-service-switch %mdns-host-lookup-nss))
```

## Review checklist

- **New `user-account` without `password`: the account is locked** (`!` in `/etc/shadow`), so nobody can log in as that user. After the first reconfigure, set a password as root with `sudo passwd <name>`, or set `(password (crypt "initial" "$6$salt"))` and tell the user to change it. Existing users keep their password.
- Supplementary groups: `wheel` for sudo, `netdev` for NetworkManager without root, `audio`, `video`, `input` for raw input devices, `kvm` for VMs. A group must exist: base groups are predefined, and others go in `(groups (cons (user-group (name "x")) %base-groups))`.
- File systems inside LUKS need `(dependencies mapped-devices)`. Labels and UUIDs must match `lsblk -f`. Keep `%base-file-systems`.
- Swap file: create it before reconfiguring (`dd`, `chmod 600`, `mkswap`).
- Kernel: `(kernel …)` and `(firmware …)` are often from a non-free channel. `(initrd microcode-initrd)` needs that too. Add kernel arguments with `(kernel-arguments (append '("foo=bar") %default-kernel-arguments))`.
- `initrd-modules`: append to `%base-initrd-modules`, for example virtualization storage drivers (`hv_storvsc`, `hv_vmbus` on Hyper-V; `virtio_*` on KVM). A missing storage driver means "cannot find root device" at boot.
- Each service type appears once. Two instances of a non-extensible service fail, and so does a service already in `%desktop-services`, such as NetworkManager or elogind.
- `use-service-modules` and `use-package-modules` must cover every variable used. An unbound variable is almost always a missing module.

## Services: add, extend, modify

```scheme
(service openssh-service-type)                                   ; default config
(service screen-locker-service-type
         (screen-locker-configuration
          (name "swaylock")
          (program (file-append swaylock "/bin/swaylock"))
          (using-pam? #t) (using-setuid? #f)))
(udev-rules-service 'steam-devices steam-devices-udev-rules)      ; gamepads, VR
(simple-service 'mtp udev-service-type (list libmtp))            ; extend a service
(simple-service 'mount-helpers privileged-program-service-type    ; setuid helpers
                (map file-like->setuid-program
                     (list (file-append nfs-utils "/sbin/mount.nfs")
                           (file-append ntfs-3g "/sbin/mount.ntfs-3g"))))
(simple-service 'my-job mcron-service-type
                (list #~(job "0 3 * * *" "my-backup --quiet")))
```

`privileged-program-service-type` and `file-like->setuid-program` are the current names. Older configs use `setuid-program-service-type`.

Modify a service inside `%desktop-services` or `%base-services`:
```scheme
(modify-services %desktop-services
  (guix-service-type config =>
    (guix-configuration (inherit config)
                        (substitute-urls …) (authorized-keys …)))
  (delete gdm-service-type))           ; remove one
```
Wrap such tweaks in a procedure, such as `(define (with-my-substitutes services) …)`, so several configs share them.

## Images and VMs

```scheme
;; guix system image --image-type=iso9660 installer.scm
(use-modules (gnu) (gnu system install) (gnu packages package-management))
(operating-system
  (inherit installation-os)
  (initrd-modules (append '("hv_storvsc" "hv_vmbus") %base-initrd-modules))
  (packages (append (list git curl) (operating-system-packages installation-os)))
  (services
   (modify-services (operating-system-user-services installation-os)
     (guix-service-type config =>
       (guix-configuration (inherit config)
                           (channels %my-channels)                    ; preset channels
                           (guix (guix-for-channels %my-channels)))))))
```
- To derive an image from an existing config: `(operating-system (inherit (load "host.scm")) (initrd base-initrd))`. Loading configs relative to the current file depends on the working directory, so run it from that directory.
- `--image-type` values: `iso9660`, `efi-raw`, `qcow2`, `mbr-raw`… (`guix system image --list-image-types`).

## Troubleshooting reconfigure

| Symptom | Fix |
|---|---|
| Long Guile backtrace | Read the bottom frames (`guix-build-debugging`). |
| Channel `object not found` or "not a descendant" | `guix-channels`: pull from an existing branch, or `--allow-downgrades`. |
| Unbound variable | Missing `use-*-modules`, or a renamed service or package. Check with `guix system search <name>` for services and `guix show` for packages. |
| "service X provided more than once" | Duplicate of a service already in `%desktop-services`. Use `modify-services` instead. |
| Boot fails after a kernel or initrd change | Pick the previous generation in GRUB, then fix the config. |

Before running reconfigure, `reboot` or anything that changes the live system, ask the user. Report what you built versus what you applied.
