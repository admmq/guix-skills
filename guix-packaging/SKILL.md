---
name: guix-packaging
description: Write, update, or fix GNU Guix package definitions (Guile Scheme `package` records), covering sources and hashes, build systems, inputs, phases, wrappers, tests, variants and descriptions. Use when asked to package software for Guix, bump a package to a newer upstream version, fix a package that stopped building after `guix pull`, port or extend a Guix recipe in a personal channel, or judge whether some software can be packaged for Guix.
---

# Guix packaging

Related skills: `guix-build-debugging` (build, logs, smoke tests), `guix-local-development` (a `guix.scm` for the project's own repo), `guix-channels` (where packages live), `guix-foreign-binaries` (prebuilt or proprietary binaries).

References in this skill:
- `references/build-systems.md`: notes per build system (gnu, cmake, meson, copy, trivial, qt, pyproject, go, cargo, emacs)
- `references/patterns.md`: snippets for recurring tasks
- `references/packagability-assessment.md`: how to answer "can X be packaged for Guix?"

## Workflow

1. **Look for existing work first.** Use `guix search <name>`, `guix show <name>` (its `location:` gives the file), and `guix edit <name>`, or grep a Guix checkout: `grep -rn '(name "foo")' gnu/packages/`. Check the other channels too (`guix describe`). If Guix has an older version, start from its recipe, since it already contains fixes you'd otherwise rediscover. Then verify each flag (see *Distrust inherited flags*).
2. **Study upstream before writing.** Read the build files (CMakeLists.txt, meson.build, Makefile, pyproject.toml, go.mod, Cargo.toml) for:
   - dependencies
   - bundled or vendored libraries
   - anything fetched at build time (FetchContent, conan, npm, submodules, downloads)
   - version stamping from git history
   - tests needing network or a display
   - odd install layouts

   For shell scripts, grep every external command they call.
3. **Pin the source and compute its hash** (see below). Never invent a hash.
4. **Write the definition** in current Guix style (template below).
5. **Build.** Run long builds in the background. On failure, read the log instead of guessing (`guix-build-debugging`).
6. **Smoke-test the output** in a clean environment, then **lint**: `guix lint -L <dir> -n <pkg>`.
7. **Report honestly** what was built and run and what wasn't. For example: "builds; `--version` works; GPU backend not exercised". Don't commit unless asked.

## Template (current style)

```scheme
(define-public foo
  (package
    (name "foo")
    (version "1.2.3")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://example.org/foo")
             (commit (string-append "v" version))))
       (file-name (git-file-name name version))
       (sha256
        (base32 "<52-char nix-base32 hash>"))))
    (build-system cmake-build-system)
    (arguments
     (list
      #:configure-flags
      #~(list "-DFOO_USE_SYSTEM_BAR=ON")
      #:phases
      #~(modify-phases %standard-phases
          (add-after 'unpack 'fix-data-dir
            (lambda _
              (substitute* "src/paths.h"
                (("/usr/share") (string-append #$output "/share"))))))))
    (native-inputs (list pkg-config))
    (inputs (list bar zlib))
    (home-page "https://example.org/foo")
    (synopsis "Short phrase, no leading article, no final period")
    (description
     "Full sentences, two spaces after each period.  Texinfo markup:
@code{foo_init}, @command{foo}, @file{~/.config/foo}, @acronym{ML, Machine
Learning}.")
    (license license:gpl3+)))
```

- Inputs are plain lists of package variables, with no labels. A non-default output is written `(list glib "bin")`.
- `arguments` is `(list #:key value …)` with gexps (`#~`, `#$`, `#$@`). Don't use old quasiquoted argument lists.
- Typical imports are `((guix licenses) #:prefix license:)`, `(guix packages)`, `(guix gexp)`, `(guix utils)`, `(guix git-download)` or `(guix download)`, and `(guix build-system <x>)`, plus each `(gnu packages <m>)` that defines an input. `guix show <input>` tells you its module. Remove imports you don't use.

## Sources, versions, hashes

- **Release tag:** `(commit (string-append "v" version))`. Check upstream's tag format first (`v1.2`, `1.2`, `foo-1.2`).
- **Unreleased commit:**
  ```scheme
  (let ((commit "<full 40-char sha>")
        (revision "1"))
    (package
      (version (git-version "1.4.0" revision commit)) ; → 1.4.0-1.<sha7>
      (source (origin (method git-fetch)
                      (uri (git-reference (url "…") (commit commit)))
                      …))
      …))
  ```
  Use the latest tag the commit descends from as the base version (`git describe --tags`), not `0.0.0`. Bump `revision` whenever `commit` changes.
- **Hash of a git checkout:** clone at the exact ref, then hash it without `.git`:
  `git clone --depth 1 --branch v1.2.3 URL d && guix hash -x -S nar d`.
  For submodules, add `(recursive? #t)` to the `git-reference` and clone with `--recurse-submodules`, but prefer unbundling them (below).
- **Hash of a tarball:** `guix download URL` prints it and also stores the file.
- A wrong placeholder hash makes the build fail and print the actual hash. That's acceptable only after you've inspected the content yourself. Otherwise leave an obvious placeholder and say so.
- On a slow network, pre-seed the store with a local checkout using `guix-build-debugging/scripts/add-checkout-to-store.scm`.
- Upstream renamed or moved its repo? Point `url` at the new location and keep the language-level name (Go import path, crate name) as upstream declares it. Add a comment.

## Inputs

- **`native-inputs`**: tools that run during the build (pkg-config, qttools, pandoc, python for build scripts, test-only deps).
- **`inputs`**: libraries linked against, and programs used at run time.
- **`propagated-inputs`**: only when dependents need them too (Python, Go and Emacs libraries; headers named in a `.pc` file's `Requires`). Never propagate just to make something work.
- **Refer to inputs by package, not by label:**
  - `#$(this-package-input "bar")` or `#$(this-package-native-input "bar")`
  - `(search-input-file inputs "/bin/grub-install")` inside `(lambda* (#:key inputs #:allow-other-keys) …)`
  - `#$(file-append bar "/bin/bar")`
  - Avoid `(assoc-ref inputs "x")` and `%build-inputs`. Labels are package *names*, which change when Guix renames a package and keeps the old variable as an alias. The lookup then silently returns `#f`, and the build dies with a confusing type error.
- **An `origin` can be an input.** Its label is its file name, so `(this-package-native-input "foo-ui-1.0.tar.gz")` works. You can also define it as a top-level variable and reference it as `#$foo-ui-origin` in a gexp.
- Drop inputs the build never uses. Check configure output and `ldd` or `readelf -d` on the result.

## Phases

- Use `modify-phases` with `add-after`, `add-before`, `replace` and `delete`. Name each phase for what it does, and add a comment saying *why* it's needed.
- **`substitute*` silently does nothing when a pattern doesn't match.** After writing one, check that it applied: grep the file in a kept build tree (`-K`), or check the installed result. Capture groups bind variables: `(("^([[:blank:]]*)FOO=.*" _ indent) (string-append indent "FOO=…\n"))`.
- Helpers: `invoke` (raises on non-zero exit), `with-directory-excursion`, `install-file`, `copy-recursively`, `mkdir-p`, `delete-file-recursively`, `find-files`, `which`.
- Make-based builds: `#:make-flags #~(list (string-append "CC=" #$(cc-for-target)) (string-append "PREFIX=" #$output))`. Use `(delete 'configure)` when there is no configure script.
- When the project is in a subdirectory, use `(add-after 'unpack 'chdir (lambda _ (chdir "subdir")))`.

## Things upstream builds expect that Guix lacks

- **Network access during the build.** FetchContent, conan, npm, pip, `go mod download` and asset downloads all fail. Patch them out and provide the content as origins. If building an asset from source is impractical, such as a prebuilt web UI from a release page, fetch the release asset as an extra origin, unpack it where the build looks for it, and say so in a comment.
- **Bundled libraries.** Guix uses system libraries. Delete bundled copies in an origin `snippet` or an early phase, and enable the "use system X" option. Package upstream's pinned git submodules as separate `origin`s and copy them in after `unpack`.
- **A `.git` directory.** Anything derived from git history (version string, build number, commit id) must be passed in through configure flags or environment variables. Otherwise the tool prints "0 (unknown)".
- **FHS paths.** Replace `/usr/…` and `/bin/…` references. Shebangs are already fixed by the automatic `patch-shebangs` phase.
- **Deploy and bundling steps for /opt-style tarballs.** Disable Qt deploy scripts, `install(RUNTIME_DEPENDENCIES)` filters that only exclude `/usr/lib`, and RPATH rewriting. Guix's RUNPATH is already right.
- **Desktop files in the prefix root.** Move `.desktop` files to `share/applications`, set `Exec=` to `#$output/bin/…` and `Icon=` to a bare name, put icons in `share/icons/hicolor/<size>/apps/`, and delete systemd units and post-install scripts.

## Runtime dependencies

- ELF programs find their libraries through RUNPATH, which Guix sets from the inputs. The `validate-runpath` phase checks it.
- Programs that need plugins, data or environment variables at run time get a wrapper. Use `wrap-program`, or the build system's own wrapper (qt-build-system's `qt-wrap`, glib-or-gtk's). A wrapper renames the real program to `.foo-real`. That breaks programs that use their own file name (`$0`), and `qt-wrap` can also wrap non-executable data files that live in `bin/`. Unwrap those in a phase after `qt-wrap` (`references/patterns.md`).
- Shell scripts that call external commands should have every command they call in `inputs`. Grep the script, compare with its own dependency check, and remember less obvious ones (`tput` comes from ncurses). Then either substitute each command with its store path, or inject one `export PATH=…` line after the shebang. The second survives upstream edits better (`references/patterns.md`).

## Tests

- Run them if you can. Disable them (`#:tests? #f`) only with a comment explaining why: they need network, download models, need a display, or there is no test suite.
- Prefer skipping individual tests to disabling all of them. Use `#:test-flags` (`-k "not test_x"`, ctest `-E regex`, go `-skip`).
- If tests are optional in the build system and you aren't running them, don't build them either (`-DFOO_BUILD_TESTS=OFF`).
- For tests that need a writable home, add `(setenv "HOME" "/tmp")` in a phase before `check`.

## Performance-sensitive code

- Guix builds for the baseline architecture, without `-march=native`. SIMD-heavy libraries without runtime CPU dispatch therefore run as plain x86-64, without AVX2 or FMA. Prefer upstream options that build several CPU variants and pick one at run time. Otherwise set `(properties '((tunable? . #t)))` so users can build with `--tune`.
- **Distrust inherited flags.** Recipes, including Guix's own, sometimes pass options that the upstream build silently overrides, such as a CMake `set()` that clobbers a cache option, or `*_DEFAULT` variables nothing reads. Confirm in the build files and the configure log that every feature you rely on is actually enabled. Remove dead flags and the inputs that only existed for them.

## Variants and transformations

```scheme
(define-public foo-extra
  (package
    (inherit foo)
    (name "foo-extra")
    (arguments
     (substitute-keyword-arguments (package-arguments foo)
       ((#:configure-flags flags) #~(cons "-DEXTRA=ON" #$flags))
       ((#:phases phases)
        #~(modify-phases #$phases
            (add-before 'configure 'set-env
              (lambda _ (setenv "FOO_KEY" "value")))))))
    (inputs (modify-inputs (package-inputs foo)
              (append baz)))))
```

- `modify-inputs` clauses: `(append x …)`, `(prepend x …)`, `(delete "name" …)`, `(replace "name" new)`.
- One-off variants without code: `--with-source=pkg=DIR-or-URL`, `--with-commit=pkg=SHA`, `--with-git-url`, `--with-input=a=b`, `--tune`.
- If a channel package has the same name as one in Guix, the CLI picks the higher version. In Scheme, import the channel module with `#:prefix` so it's unambiguous which one you mean.

## Metadata and style

- **synopsis:** short, no leading article, no final period.
- **description:** say what the software does for the user, in full sentences with Texinfo markup and two spaces between sentences. Avoid marketing language.
- **license:** read LICENSE or COPYING and the file headers. "or (at your option) any later version" means `gpl3+`, not `gpl3`. Use `(guix licenses)` symbols. For non-free licenses, see `guix-foreign-binaries`.
- `guix style -f file.scm` reformats a file. `guix style <pkg>` modernizes old-style inputs.
- Comment non-obvious version choices, for example "version bundled by X; bump together".

## A package broke after `guix pull`

The usual cause is a change in Guix itself:

| Symptom | Likely cause |
|---|---|
| unbound variable | a package variable was renamed or removed |
| `#f` from a label lookup | a package was renamed (the old variable is kept as an alias) |
| no code for module | a module was moved or split |
| build failure | a new major version of a dependency |

Find the change with `git log -S'<name>' -- gnu/packages/` in a Guix checkout. While you're fixing it, check whether upstream has a newer release, and whether old workarounds are still needed. Delete workarounds that no longer are.
