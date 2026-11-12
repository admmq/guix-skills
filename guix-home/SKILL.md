---
name: guix-home
description: Manage a user's dotfiles, user packages, environment and user services declaratively with Guix Home (home-environment). Covers packages by specification, home-files and XDG config files, local-file naming rules, shells, channels via home-channels-service-type, user Shepherd services, and the reconfigure, container test and roll-back workflow. Use when editing a home-configuration.scm, migrating dotfiles to Guix Home, or when guix home reconfigure fails or overwrites files.
---

# Guix Home

Related skills: `guix-services` (writing home services), `guix-channels`, `guix-system-configuration` (the system-level counterpart).

## Workflow

```sh
guix home import ~/src/home-config      # bootstrap a config from existing dotfiles
guix home container home.scm            # try it in an isolated container first
guix home reconfigure home.scm          # apply (ask first)
guix home describe / list-generations / roll-back
```
Reconfigure **backs up** conflicting existing files to `~/<timestamp>-guix-home-legacy-configs-backup/` and replaces them with symlinks into the store. Tell the user before taking over files they edit by hand, such as `.bashrc`.

## Skeleton

```scheme
(use-modules (gnu home)
             (gnu home services)
             (gnu home services shells)
             (gnu home services guix)          ; home-channels-service-type
             (gnu packages)
             (gnu services)
             (guix gexp)
             ((my-channel vars) #:prefix my:))

(home-environment
  (packages (specifications->packages
             (list "git" "curl" "openssh" "emacs-pgtk" "emacs-magit")))
  (services
   (append
    (list
     (service home-channels-service-type my:%channels)   ; manages channels.scm
     ;; Paths relative to $HOME.  local-file paths are relative to THIS file.
     (service home-files-service-type
              `((".config/waybar/config.jsonc" ,(local-file "waybar/config.jsonc"))
                (".config/swaylock/config"
                 ,(local-file "swaylock/config" "swaylock-config"))))
     (simple-service 'env home-environment-variables-service-type
                     '(("EDITOR" . "emacsclient"))))
    %base-home-services)))
```

## Gotchas

- **`local-file` names** default to the file's basename, which must be a valid store name: no leading dot. Give an explicit name, as in `(local-file "dot-bashrc" "bashrc")`, and use it when a basename like `config` is ambiguous too.
- `local-file` paths are resolved relative to the config file, not the working directory.
- `home-xdg-configuration-files-service-type` takes paths relative to `~/.config`. `home-files-service-type` takes paths relative to `~`.
- Package specifications (`"name"` or `"name@version"`, or `"name:output"`) are resolved with the **pulled** `guix`. Packages from a channel must be in `channels.scm` and pulled first, or reconfigure with `-L <channel-dir>`.
- `home-bash-service-type` generates `.bashrc` and `.bash_profile`. Put customizations in its `aliases`, `environment-variables` and `bashrc` fields, or the user's hand edits get backed up and replaced.
- Some packages need system-level support and don't work from Home alone: setuid helpers, udev rules, system daemons, PAM. Use the system config for those.
- Certificates: include `nss-certs` if the system doesn't already provide it, for TLS in user programs.
