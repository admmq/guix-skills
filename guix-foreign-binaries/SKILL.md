---
name: guix-foreign-binaries
description: Run or package prebuilt, proprietary or FHS-dependent software on Guix. Covers why foreign ELF binaries fail ("No such file or directory" with no FHS dynamic linker), guix shell --container --emulate-fhs, patchelf-based repackaging (interpreter, RUNPATH vs RPATH for dlopen'd add-ons), bubblewrap FHS launchers for apps that download binaries at run time (editor extensions, language servers), wrapper environment for Electron and GTK apps, non-free licences and channels, and Windows programs via Wine. Use when a downloaded binary, AppImage-like bundle, Electron app or game won't start on Guix, or when packaging a vendor binary release.
---

# Foreign binaries on Guix

Related skills: `guix-packaging`, `guix-host-environment`. For Wine, see `references/wine.md`.

## Why they fail

A prebuilt ELF names its interpreter `/lib64/ld-linux-x86-64.so.2` (`/lib/ld-linux-aarch64.so.1` on ARM) and expects libraries in `/usr/lib`. Guix System has neither, so the kernel reports **"No such file or directory" for a file that clearly exists**. Confirm with `file ./prog` or `readelf -l ./prog | grep interpreter`.

## Option 1: run it in an FHS container (no packaging)

```sh
guix shell -CF --network --share=$HOME/data=/data \
  coreutils bash glibc gcc:lib zlib libx11 … -- ./prog
```
- `-C` creates a container and `-F` (`--emulate-fhs`) adds `/lib`, `/usr`, `/lib64` and an `ld.so.cache`.
- To run a GUI inside, share the display: `--preserve='^DISPLAY$' --preserve='^WAYLAND_DISPLAY$' --preserve='^XDG_RUNTIME_DIR$' --expose=$XDG_RUNTIME_DIR`, plus `--share=/tmp/.X11-unix` for X11.
- Find missing libraries iteratively. Inside the container, run `ldd ./prog | grep 'not found'` and add packages until nothing is missing.

## Option 2: repackage with patchelf (a proper package)

Use `copy-build-system` to install the release tree, then fix every ELF file:
```scheme
(add-after 'install 'patch-elf-files
  (lambda* (#:key inputs #:allow-other-keys)
    (let* ((ld.so (search-input-file inputs #$(glibc-dynamic-linker)))
           (libs  (cons* (dirname ld.so)
                         (map (lambda (d) (string-append d "/lib"))
                              (list #$@(map input->gexp-input %app-libraries))))))
      (for-each
       (lambda (file)
         (let* ((elf  (parse-elf (call-with-input-file file get-bytevector-all
                                   #:binary #t)))
                (info (elf-dynamic-info elf)))
           (when info                                   ; skip static binaries
             (when (any (lambda (s) (= PT_INTERP (elf-segment-type s)))
                        (elf-segments elf))
               (invoke "patchelf" "--set-interpreter" ld.so file))
             (invoke "patchelf" "--set-rpath"
                     (string-join (delete-duplicates
                                   (append (elf-dynamic-info-rpath info)
                                           (elf-dynamic-info-runpath info)
                                           libs))
                                  ":")
                     file))))
       (find-files (string-append #$output "/lib/app")
                   (lambda (f s) (and (eq? 'regular (stat:type s)) (elf-file? f))))))))
```
- Needed modules: `#:modules '((guix build copy-build-system) (guix build utils) (guix elf) (ice-9 binary-ports) (srfi srfi-1) …)`, and `(native-inputs (list patchelf))`.
- **dlopen'd add-ons with no RUNPATH** (Node.js native modules, plugins) can't find `libstdc++` and friends. That's because `DT_RUNPATH` applies only to the object's own dependencies, while `DT_RPATH` on the main executable also covers libraries it loads. After `validate-runpath` (which only checks RUNPATH), convert the main binary: `patchelf --remove-rpath exe` and then `patchelf --force-rpath --set-rpath <path> exe`.
- Libraries that are loaded by name at run time (`libGL`, `libvulkan`, `libnss3`, `libsecret`, `libnotify`, pulseaudio, `libxkbfile`…) never appear in `ldd`. Read the vendor's .deb or .rpm dependency list to find them.
- **Launcher scripts** in vendor bundles call `which`, `grep`, `tr` and `id` from `PATH`, and compute their install dir from `$0`. Substitute absolute store paths and hard-code the install dir.
- **Wrapper environment** for Electron and GTK apps that expect a desktop distro:
  - `XDG_DATA_DIRS` must include `gtk+/share` and `gsettings-desktop-schemas/share`. Without GSettings schemas, GTK file dialogs abort.
  - `PATH` must include `xdg-utils` and `glib:bin` (`gio`) for opening links and moving files to the trash.
  - When `/etc/fonts/fonts.conf` is missing, as on Guix System, set `FONTCONFIG_PATH` to `fontconfig/etc/fonts` for bundled Fontconfig. `FONTCONFIG_FILE` alone loses the included files.
  - **Append** to search paths rather than replacing them, since child processes such as integrated terminals inherit them.
- Desktop file and icons: install what the vendor's own packages install (`share/applications`, `share/icons/hicolor/…`, shell completions). Electron uses the `.desktop` name for window grouping.
- `(supported-systems '("x86_64-linux" "aarch64-linux"))` should match what the vendor ships.

## Option 3: FHS launcher for apps that fetch binaries at run time

Editor extensions, language servers and SDK managers download more prebuilt programs later, and those can't be patched at build time. Wrap the app in a bubblewrap launcher that builds a light FHS view:
- Build an environment with `union-build` over common FHS packages (`bash coreutils grep sed gawk findutils tar gzip xz which procps glibc-for-fhs glibc-utf8-locales tzdata openssl zlib (gcc "lib") (util-linux "lib") icu4c libsecret mit-krb5 ncurses/tinfo curl expat`), plus an `ld.so.cache` from `ldconfig -X -f ld.so.conf -C …`.
- Exec `bwrap`, binding every top-level host directory except `/bin /lib /lib64 /sbin /usr /etc`. Symlink `/bin`, `/lib`, `/lib64` and `/usr/*` to the environment. Rebuild `/etc` as symlinks into a bind of the host `/etc`, so that `resolv.conf` and others stay live. Bind the environment's `ld.so.cache`.
- Set a marker variable (for example `APP_FHS=1`) and **exec directly when it's already set, or when the host already has an FHS loader**. That way nested shells and foreign distros skip the sandbox.
- Append the environment's bin dirs to `PATH` and its locales to `GUIX_LOCPATH`.
- Caveat: setuid programs (`sudo`) don't work inside a user namespace. Document it.

## Licences and where it belongs

- Proprietary binaries go in a personal channel or a non-free channel, never Guix proper. Non-free channels usually provide an `(undistributable "URL")` or `nonfree` licence constructor.
- Some non-free channels provide build systems for binary repackaging, FHS containers for games and launchers, firmware, and non-libre kernels. Check what the user's channels offer (`guix describe`, then grep their `build-system` directories) before hand-rolling one.
