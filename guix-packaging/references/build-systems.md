# Build systems: practical notes

Pick the build system that matches upstream's build tool. Every build system's phases can be adjusted with `modify-phases`. The full reference is the "Build Systems" node of the Guix manual (`info guix "Build Systems"`), or `guix/build-system/*.scm` and `guix/build/*-build-system.scm` in a Guix checkout. Reading those files is the fastest way to learn what a keyword actually does.

## gnu-build-system (`(guix build-system gnu)`)

This is the default, for autotools and plain Makefiles. Most other build systems reuse its phases.
- Main phases: `unpack`, `bootstrap`, `patch-source-shebangs`, `configure`, `build`, `check`, `install`, `patch-shebangs`, `strip`, `validate-runpath`, `compress-documentation`.
- Keywords: `#:configure-flags`, `#:make-flags`, `#:tests?`, `#:test-target` (default `"check"`), `#:parallel-build?`, `#:parallel-tests?`.
- Plain Makefile with no configure: `(delete 'configure)` and pass `PREFIX=`/`DESTDIR`-style variables in `#:make-flags`.
- **There is no `cc` in the build environment.** Pass `(string-append "CC=" #$(cc-for-target))`, and likewise `CXX` with `cxx-for-target`.
- To use build-side helpers from another build system (for example the Emacs utilities in a C package):
  ```scheme
  #:modules '((guix build gnu-build-system) (guix build utils) (guix build emacs-utils))
  #:imported-modules `(,@%default-gnu-imported-modules (guix build emacs-utils))
  ```
  After that, a phase can call `(emacs-generate-autoloads name dir)` and `(emacs-byte-compile-directory dir)`.

## cmake-build-system

- `#:configure-flags #~(list "-DFOO=ON" …)`. `#:build-type` defaults to a release-type build.
- Tests run through ctest. `#:test-exclude "regex"` skips matching tests. If tests aren't run, prefer turning off upstream's test build option (`-DBUILD_TESTING=OFF` or a project-specific option) instead of building and then ignoring them.
- Upstream "use system X" switches (`-DFOO_USE_SYSTEM_BAR=ON`) are how you unbundle.
- Confirm options in the configure log. Upstream `set()` calls can silently override cache options passed with `-D`.
- To test a computed boolean in a gexp, splice a quoted list: `#$@(if (target-x86?) '("-DFOO_X86=ON") '())`.

## meson-build-system

- `#:configure-flags #~(list "-Dfeature=enabled" "-Dtests=false")`. Ninja does the building, and tests run with `meson test`.

## copy-build-system

For scripts, data or prebuilt files: there is nothing to compile, you only install.
```scheme
(build-system copy-build-system)
(arguments
 (list #:install-plan
       #~'(("bin/tool"          "bin/")             ; trailing slash: into dir
           ("share/man/man1/tool.1" "share/man/man1/")
           ("share/tool"        "share/tool")       ; directory → directory
           ("lib" "lib" #:include-regexp ("\\.so")))))
```
- Phases such as `patch-shebangs` and `validate-runpath` still run.
- Prefer it to `trivial-build-system` whenever the job is "put files in place, plus a few fixes".

## trivial-build-system

You write the whole builder. There are no phases, no automatic shebang patching and no stripping.
```scheme
(build-system trivial-build-system)
(arguments
 (list #:modules '((guix build utils))
       #:builder
       #~(begin
           (use-modules (guix build utils))
           (let ((share (string-append #$output "/share/foo")))
             (mkdir-p share)
             (copy-file #$some-origin (string-append share "/data.bin"))))))
```
- Reference origins and packages directly with `#$`. `(source …)` can be `#f`.
- It's good for meta-packages, launchers (`program-file`/symlink) and bundling several origins together.

## qt-build-system

This is CMake plus a `qt-wrap` phase. The wrapper sets `QT_PLUGIN_PATH`, QML import paths and `XDG_DATA_DIRS` for each program in `bin/`.
- **The default Qt is Qt 5.** For Qt 6, pass `#:qtbase qtbase`.
- Common inputs:
  - `qtwayland`: Wayland support
  - `qtsvg`: SVG icons, including window icons
  - `qtmultimedia`, `qtdeclarative`: QML
  - `qttools` (native): LinguistTools and `lrelease`
- `bin/foo` becomes a small shell wrapper around `bin/.foo-real`. Remember that when inspecting binaries or debugging them with gdb.
- `qt-wrap` also wraps non-ELF data files that upstream installed in `bin/`. Restore them in a phase after `qt-wrap` (`patterns.md`).
- Disable upstream deploy steps such as `qt_generate_deploy_app_script`, which copy Qt into the prefix.

## pyproject-build-system

- Add the build backend named in `pyproject.toml` to `native-inputs`: `python-setuptools` (plus `python-wheel` for older setups), `python-hatchling`, `python-poetry-core` or `python-flit-core`.
- Choosing the test runner: with no `#:test-backend`, it uses pytest if available, then stestr, nose, setup.py, then `python -m unittest`. Pass arguments with `#:test-flags`. For a unittest tree, `#:test-flags #~(list "discover" "-s" "tests")`.
- The `sanity-check` phase imports the package's top-level modules and entry points, which catches missing runtime dependencies. Put those in `propagated-inputs` for Python libraries.
- When the project sits in a subdirectory of the repo, add a `chdir` phase after `unpack`.

## go-build-system

- `#:import-path "github.com/org/repo"` is the module path from `go.mod`, which can differ from the repo URL after a rename. For multi-module repos, use `#:unpack-path` for the repo root and `#:import-path` for the sub-module.
- Go library dependencies go in `propagated-inputs` and are named `go-<import-path-with-dashes>`. Programs often set `#:install-source? #f`.
- Bootstrap new libraries with `guix import go -r module@version`, then review what it generates.
- Test suites often break with newer Go defaults (GODEBUG changes, stricter parsers). Disable only with a comment that names the reason.
- When a dependency needs a newer commit than Guix packages, add a variant with a distinct name (for example `…-next`) rather than overriding the Guix package.

## cargo-build-system

- Applications set `#:install-source? #f`. Workspaces need `#:cargo-install-paths`.
- Crate dependencies come from the lockfile importer, not from hand-written packages:
  ```sh
  guix import -i <module-file.scm> crate -f /path/to/Cargo.lock <name>
  ```
  The package then uses `(inputs (cargo-inputs '<name>))`, or in a channel `(cargo-inputs '<name> #:module '(my-channel rust-crates))`. The module has to export `lookup-cargo-inputs`; a template lives in Guix's `etc/teams/rust/`.
- The importer fails on git dependencies whose commit is no longer on any branch ("object not found"). Hand-write an origin pinned to the SHA, or get upstream to use a released crate.
- Vendored C libraries in `-sys` crates (OpenSSL via `openssl-src`, llama.cpp, AWS-LC, sqlite, zstd) need unbundling or disabling. Turn off upstream features that pull them in, such as `vendored`, self-updaters and local-inference backends.
- `rust-toolchain.toml` pins are ignored, since Guix has no rustup. What matters is whether Guix's `rust` meets `rust-version` in `Cargo.toml`.

## emacs-build-system

- It byte-compiles and generates autoloads automatically. Select files with `#:include '("\\.el$")` and `#:exclude '("test\\.el")`.
- Literate configs (Org): add a phase after `unpack` that tangles with `(invoke "emacs" "--batch" …)`.
- Elisp shipped inside a non-Emacs package belongs in `share/emacs/site-lisp/<name>/` (see gnu-build-system above).

## Others to look up when needed

`meson`, `glib-or-gtk` (wraps GSettings and GIO modules), `node`, `ruby`, `dune`, `haskell`, `julia`, `zig` and `asdf` are all documented in the manual. Look at an existing package of the same kind with `guix edit <similar-pkg>`.
