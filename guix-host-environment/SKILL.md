---
name: guix-host-environment
description: How an agent should operate on a machine running GNU Guix (Guix System, or Guix on another distro) — detecting it, getting tools that aren't installed via guix shell, running Guix-provided tools under sudo, finding configs, profiles, services and logs, and not assuming an FHS layout. Use at the start of any task on a Guix machine, and whenever a command fails with "command not found" or a path like /usr/bin/python3, /usr/lib or /lib64/ld-linux-x86-64.so.2 doesn't exist.
---

# Working on a Guix host

Related skills: `guix-local-development` (dev shells for a project), `guix-foreign-binaries` (prebuilt binaries that won't start), `guix-system-configuration` (changing the system).

## Detect what you're on

| Check | Meaning |
|---|---|
| `test -e /run/current-system` | Guix System (the whole OS is declared in Scheme) |
| `command -v guix` | Guix is available (maybe on a foreign distro) |
| `guix describe` | Channels and commits of the user's current `guix` |
| `guix system describe` | Current system generation, its channels, and a store copy of the config it was built from (`configuration file:` line) |
| `guix home describe` | Whether the user manages dotfiles with Guix Home |

The user's editable system config is often not `/etc/config.scm`. Find the real one (ask, or search their repos for `(operating-system`) before suggesting edits.

## Filesystem layout: not FHS

- Software lives in `/gnu/store/<hash>-<name>-<version>/`. It is read-only and is never edited by hand.
- Guix System has **no** `/usr/bin` (except `/usr/bin/env`), `/usr/lib`, `/lib64` or dynamic linker at the FHS path. `/bin/sh` exists. `#!/usr/bin/env foo` shebangs work, while `#!/usr/bin/python3` does not.
- Profiles hold the "installed" software:
  - `~/.guix-profile`: `guix install` / `guix package`
  - `~/.guix-home/profile`: Guix Home packages
  - `/run/current-system/profile`: system-wide `packages` of the OS config
  - `~/.config/guix/current`: the user's pulled `guix`
- Setuid and privileged programs (`sudo`, `passwd`, mount helpers) are in `/run/privileged/bin`.
- Most of `/etc` is generated from the system configuration. Hand edits to managed files are lost on the next reconfigure, so change the config instead.

## Getting a tool that isn't installed

Don't ask the user to install a tool permanently just for your task. Run it ephemerally:

```sh
guix shell python -- python3 -I script.py          # python3 isn't installed by default
guix shell python python-requests -- python3 x.py   # several packages
guix shell jq -- jq . file.json
guix shell gcc-toolchain make -- make               # compilers: gcc-toolchain, not gcc
```

- Find a package by keyword with `guix search <regexp>`. Find which package ships a file or command with `guix locate <file>` (its database may need building on first use; see `guix locate --help`).
- Package names don't always match command names. The `python` package provides `python3`. `emacs-pgtk` installs a binary named `emacs`, not `emacs-pgtk`. The C compiler is `gcc`, and there is **no `cc`** command.
- The first `guix shell` for a package may download substitutes or build from source, which can take minutes. Run big ones in the background. Later runs are cached.
- `guile` is usually present as a scripting fallback, and `guix repl` gives a Guile REPL with Guix modules loaded.

## sudo with Guix tools

A tool that only exists inside `guix shell` isn't on the `PATH` of your normal shell, so `sudo nft` fails. Resolve its store path first:

```sh
sudo "$(guix shell nftables -- sh -c 'command -v nft')" list ruleset
```

For the system itself, the documented flow is `guix pull` as the user, then `sudo guix system reconfigure <config.scm>`. That uses the user's freshly pulled `guix`. Don't run `sudo guix pull` unless asked, because it only updates root's own `guix`.

## Services and logs

- Shepherd is the init system. Use `sudo herd status` (all services), `sudo herd status <svc>`, `sudo herd restart <svc>`. Run `herd status` without sudo for the user's own Guix Home services.
- The syslog is `/var/log/messages` (root-only). Some services log to `/var/log/<name>.log`. Kernel messages: `sudo dmesg`.
- The service list is defined in the OS config. Read it to see what's enabled. For example, there may be no firewall service at all.

## After the user installs or removes packages

- Run `hash -r` (or open a new shell) so bash forgets cached command locations, such as an old `wine` after switching to `wine64`.
- New search-path variables (`XDG_DATA_DIRS`, `GUIX_LOCPATH`, `QT_PLUGIN_PATH`…) only appear after `. ~/.guix-profile/etc/profile` or a new login.
- Only one package per command name should be in a profile. If two packages provide the same command, remove one.

## Guardrails

- These commands change the user's system or profiles. Ask before running them: `guix pull`, `guix system reconfigure`, `guix home reconfigure`, `guix install/remove/upgrade`, `guix package -f`, `guix gc`, and `herd stop/restart` of system services.
- `guix shell`, `guix build`, `guix lint`, `guix show`, `guix search`, `guix describe` and `guix system build` are safe. They only add to the store.
- Networks may be slow or rate-limited. The GitHub API in particular gets rate-limited. Prefer `git clone --depth 1`, direct release-asset URLs, and background jobs for big downloads.
