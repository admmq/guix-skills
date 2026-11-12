---
name: guix-local-development
description: Use Guix to develop a project from its own source tree. Covers writing a guix.scm or package.scm that builds the local checkout (and the git-predicate trap where uncommitted files are dropped), dev shells with `guix shell -D -f`, adding debuggers and tools, installing from a file, and building an existing package from local sources. Use when a repo has or needs a guix.scm, when make, cc or gdb is "command not found" inside guix shell, when a local Guix build can't find a newly added file, or when the user asks how to install a package from a file.
---

# Developing a project with Guix

Related skills: `guix-packaging` (recipe details), `guix-build-debugging` (build failures), `guix-host-environment` (no FHS, missing tools).

## The project's `guix.scm`

Convention: a `guix.scm` (or `package.scm`) at the repo root whose **last expression is a package**:

```scheme
;;; Build:    guix build -f guix.scm
;;; Dev env:  guix shell -D -f guix.scm
;;; Try it:   guix shell -f guix.scm -- foo
;;; Install:  guix package -f guix.scm

(use-modules (guix packages)
             (guix gexp)
             (guix git-download)
             (guix build-system cmake)
             ((guix licenses) #:prefix license:)
             (gnu packages pkg-config))

(define %source-dir (dirname (current-filename)))

(package
  (name "foo")
  (version "0.1-git")
  (source (local-file %source-dir "foo-checkout"
                      #:recursive? #t
                      #:select? (or (git-predicate %source-dir)
                                    (const #t))))   ; not a git checkout
  (build-system cmake-build-system)
  (native-inputs (list pkg-config))
  (inputs (list …))
  (home-page "…") (synopsis "…") (description "…")
  (license license:gpl3+))
```

- With `(define-public foo (package …))`, add a bare `foo` as the last line. Otherwise `-f` gets nothing.
- `local-file`'s name argument must be a valid store name: no `/`, and no leading dot.
- Inside a channel module, `(current-source-directory)` from `(guix utils)` gives the module's directory.

### The `git-predicate` trap

`git-predicate` selects the files of the **HEAD commit's tree**, but takes their contents from disk. So:
- uncommitted edits to tracked files **are** included
- new files that are staged with `git add` but not committed are **excluded**, and the build fails with "Cannot find source file: src/new.cpp" or similar
- untracked build artifacts are excluded, which is what you want

You can commit before building, or select from Git's index instead. `references/git-index-predicate.scm` has a drop-in replacement that includes staged files. Use it as `#:select? (or (git-index-predicate %source-dir) (git-predicate %source-dir) (const #t))`.

### Releases versus local hacking

- A recipe that pins a release (`git-fetch` + hash) can still build the local tree on demand:
  `guix build -f guix.scm --with-source=foo=$PWD`, and the same flag works for `guix package -f`.
- A recipe that uses `local-file` always builds whatever is on disk. Say which kind you've written in the file's header comment.

## Installing from a file

- `guix install` only accepts package *names*. For a file, use `guix package -f guix.scm` (`--install-from-file`). Run it again after changes to upgrade.
- `guix upgrade` won't see it, because it isn't in any channel. Remove it with `guix remove <name>`.
- To install by name, turn the file into a module (`(define-module (foo) #:use-module …)` plus `define-public`) and run `guix install -L <dir> foo`, or put it in a channel (`guix-channels`).

## Dev shells

```sh
guix shell -D -f guix.scm                 # build deps of the package (NOT the package)
guix shell -f guix.scm                    # the built package itself (no compilers)
guix shell -D -f guix.scm gdb valgrind    # -D applies only to the next item; extras are plain
guix shell -D -f guix.scm --pure          # drop host env: exposes undeclared deps
guix shell -m manifest.scm                # reproducible tool set, committed to the repo
```

- `-f` alone gives the finished program, so `make` and `gcc` are missing. That's the most common confusion, and `-D` is the fix.
- **No `cc` command exists.** `make`'s built-in `CC` is `cc`, so implicit rules fail. Either run `make CC=gcc`, or add this to the Makefile:
  ```make
  # make's built-in default is cc, which Guix lacks
  ifeq ($(origin CC),default)
  CC = gcc
  endif
  ```
  `CC ?= gcc` does **not** work, because make's built-in default already counts as set. In the package recipe, pass `CC=` explicitly with `cc-for-target`.
- For a manifest with the dev inputs plus tools, use `(concatenate-manifests (list (package->development-manifest foo) (specifications->manifest '("gdb"))))`.
- Debugging: gdb inside the shell works on the locally built binary. Programs built inside a dev shell aren't wrapped, unlike the packaged version, so Qt and GTK programs may lack plugins or schemas there.
- Variables from the user's profile can leak in and change behaviour, for example `EMACSLOADPATH` while testing Emacs code. Unset them (`env -u VAR …`) or use `--pure`.
- Commands named differently than on other distros will break README instructions. `emacs-pgtk` installs `emacs`, and the `python` package provides `python3`. Check with `ls $(guix build <pkg>)/bin`.
- `guix shell --container` (`-C`) gives an isolated environment. Add `--network`, `--share=DIR` or `--expose=DIR` as needed. Add `-F` (`--emulate-fhs`) for tools that expect `/lib64` and `/usr` (`guix-foreign-binaries`).

## Checks before calling it done

1. `guix build -f guix.scm` succeeds from a clean state, and also from another directory, since `current-filename` must resolve correctly.
2. `guix shell -D -f guix.scm` still works, then `make` or the build tool runs inside it.
3. If files were added, confirm they reached the source. Run `guix build -f guix.scm -S`, which prints the source store path, and list it.
