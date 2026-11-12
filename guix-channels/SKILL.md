---
name: guix-channels
description: Create, maintain and use Guix channels, meaning personal or third-party package repositories. Covers .guix-channel layout and dependencies, module and file naming, patches, testing with -L before pushing, channels.scm, pinning and time-machine, channel authentication, substitute servers for channel packages, name clashes with Guix packages, and errors after branch deletions or history rewrites ("object not found", "not a descendant"). Use when adding packages or services to a channel, editing channels.scm, or when guix pull or reconfigure fails because of a channel.
---

# Guix channels

Related skills: `guix-packaging`, `guix-services`, `guix-build-debugging`, `guix-system-configuration`.

## Layout

```
repo/
├── .guix-channel                 # metadata (required for directory/dependencies)
├── .guix-authorizations          # optional: signing keys allowed to commit
├── channel/                      # = (directory "channel") in .guix-channel
│   └── my-channel/
│       ├── packages/foo.scm      # (define-module (my-channel packages foo) …)
│       ├── services/bar.scm      # (define-module (my-channel services bar) …)
│       └── patches/foo-fix.patch
└── configs/ … guix.scm …         # NOT compiled: outside the channel directory
```

```scheme
;; .guix-channel
(channel
 (version 0)
 (directory "channel")
 (dependencies
  (channel
   (name other-channel)                     ; must match the name users give it
   (url "https://example.org/other-channel")
   (introduction
    (channel-introduction
     (version 0)
     (commit "<first signed commit>")
     (signer "<OpenPGP fingerprint>"))))))
```

- **`guix pull` compiles every `.scm` file under the channel directory**, recursively. Keep system configs, `guix.scm` build files and scratch scripts outside it, which is the main reason to set `(directory …)`. One broken module breaks `guix pull` for everyone using the channel.
- A module's name must match its path: `(my-channel packages foo)` ↔ `<dir>/my-channel/packages/foo.scm`.
- Export packages with `define-public`, and services and records with `#:export`.
- Patches: `(search-patches "my-channel/patches/foo-fix.patch")`. The path is resolved against the load path, so it's relative to the channel directory root.
- Don't leave test-only expressions in channel modules, such as a bare `foo` at the end for `guix build -f`.
- Keep imports minimal and remove unused ones. Import Guix modules with `#:prefix` where names could clash.

## Test before pushing

```sh
guix build -L channel <pkg>                     # build from the working tree
guix shell -L channel <pkg> -- <cmd>
guix lint -L channel -n <pkg>
guix system build -L channel configs/sys.scm    # configs that import channel modules
guix repl -L channel                            # then: ,use (my-channel packages foo)
```

To catch compile errors in all modules, as `guix pull` would see them, build the channel exactly as pull does, without touching the user's profile. Write a test channels file whose `my-channel` entry has `(url "file:///path/to/repo")` and the branch, then run `guix time-machine -C test-channels.scm -- describe`. This only sees **committed** work on that branch. For uncommitted work, use `-L channel` with `guix build -d` on one package from each module.

## Using channels

```scheme
;; ~/.config/guix/channels.scm
(cons* (channel
        (name 'my-channel)
        (url "https://example.org/my-channel")
        (branch "main")
        ;; omit introduction for unsigned personal channels (pull warns)
        (introduction
         (make-channel-introduction "<commit>"
                                    (openpgp-fingerprint "<fingerprint>"))))
       %default-channels)
```

- `guix pull` then `guix describe` to confirm. `guix describe -f channels > pinned.scm` takes a lockfile-style snapshot.
- `guix time-machine -C pinned.scm -- build foo` runs any command at the pinned revisions without changing the user's `guix`.
- Channel lists can be shared as a Scheme value in one module and reused in `channels.scm`, in Guix Home (`home-channels-service-type`), in the system's `guix-configuration` `(channels …)`, and in images via `(guix (guix-for-channels %channels))`.
- In a system or home config, refer to a channel's packages through the channel module, imported with a prefix: `((my-channel packages foo) #:prefix my:)` … `my:foo`.

## Same package name as Guix

- On the command line, the higher version wins (`guix install foo`, `guix shell foo`). With equal versions, Guix warns about ambiguity and picks one. Use `-e '(@ (my-channel packages foo) foo)'` to be explicit.
- In Scheme, the variable you import is the one you get. Import with `#:prefix` so it's obvious.
- When overriding a Guix package with a newer version, keep the same name so dependents picking by name get it. Comment which Guix recipe it follows, and when to drop it (for example "remove once Guix has ≥ X").

## Authentication and signing

- Channels with an `introduction` are authenticated on pull. Every commit must be signed by a key in `.guix-authorizations` at its parent commit. Check locally with `guix git authenticate <intro-commit> <fingerprint>`.
- Personal channels without an introduction still work, but `guix pull` warns. `--disable-authentication` exists, and shouldn't be the default advice.

## Substitutes for channel packages

Guix only uses binaries from servers whose keys are authorized:

```scheme
(modify-services %desktop-services
  (guix-service-type config =>
    (guix-configuration
     (inherit config)
     (substitute-urls (append %default-substitute-urls
                              (list "https://substitutes.example.org")))
     (authorized-keys (cons (plain-file "example.pub" "<(public-key …)>")
                            (guix-configuration-authorized-keys config))))))
```
For a one-off on a foreign distro, run `sudo guix archive --authorize < key.pub` and pass `--substitute-urls=…`. Check coverage with `guix weather --substitute-urls=… <pkg>`.

## Errors after branch deletion or a history rewrite

Profiles and systems record the exact commit of every channel. On `guix pull`, `guix system reconfigure` and `guix home reconfigure`, Guix checks that the new commit **descends from** the recorded one, to block rollback attacks. That needs the old commit:

| Error | Cause | Fix |
|---|---|---|
| `object not found` / `reference not found` for a channel commit | The recorded commit was on a branch that was deleted or force-pushed and is no longer fetchable | 1) Make sure `channels.scm` names an existing branch, then `guix pull`. 2) If reconfigure still fails on the system's old recorded commit, `sudo guix system reconfigure --allow-downgrades cfg.scm` (or `guix home reconfigure --allow-downgrades`). |
| `aborting update of channel … which is not a descendant of …` | History was rewritten, or a pinned commit is older | If the rewrite was intentional, use `--allow-downgrades`. Otherwise investigate, because this check exists for security. |

`--allow-downgrades` only skips the ancestry check. It's safe when you know the history was rewritten intentionally. Explain this to the user instead of applying it silently. Prevent the problem by not deleting branches that machines were pulled from, or by pulling from `main` before deleting them.

## Commit hygiene in a channel repo

- Build and lint before committing. Use one commit per logical change, with messages like `<module>: Add foo.` or `<module>: foo: Update to 1.2.`, or whatever style the repo already uses.
- Don't commit unless the user asks. Mention leftover test lines and uncommitted config edits you noticed.
