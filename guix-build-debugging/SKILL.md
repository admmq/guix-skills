---
name: guix-build-debugging
description: Build, verify and debug Guix packages, covering guix build options, reading Guile backtraces and build logs, keeping failed build trees, evaluating modules without building, pre-seeding sources on slow networks, smoke-testing outputs in clean environments, linting, and checking substitutes. Use when a guix build, guix shell, guix pull or reconfigure fails, when verifying a new or updated package, or when builds are slow.
---

# Building and debugging with Guix

Related skills: `guix-packaging` (writing the recipe), `guix-channels` (pull and channel errors), `guix-system-configuration` (reconfigure errors).

## Build commands

```sh
guix build -L <channel-root> <pkg>          # package from an unpublished channel checkout
guix build -f guix.scm                      # file whose last expression is a package
guix build -e '(@ (my-channel packages foo) foo)'
guix build -L <dir> -d <pkg>                # compute the derivation only: fast evaluation check
guix build -L <dir> -S <pkg>                # fetch/verify the source only (hash check)
guix build -L <dir> -n <pkg>                # dry run: what would be built vs downloaded
guix build -K …                             # keep the failed build tree
guix build --log-file <pkg>                 # path of the last build log
guix build --check <pkg>                    # rebuild and compare (reproducibility)
guix build --no-grafts …                    # skip grafting while iterating
```

- `-L` takes the directory containing the top-level module directory, which is the channel's `(directory …)` from `.guix-channel` if set. Module `(a b c)` must live at `<L>/a/b/c.scm`.
- A `guix.scm` meant for `-f` must *evaluate to* a package. `define-public` returns nothing useful, so end the file with the variable name. Remove that line before the file goes into a channel, because a bare expression in a channel module is noise.
- Packages with many dependencies spend most of their time downloading substitutes. Check with `-n` first, and run long builds in the background, polling the output.

## Catch errors before a long build

1. **Evaluate:** `guix build -L <dir> -d <pkg>`. This reports syntax errors, unbound variables and missing modules in seconds.
2. **Lint:** `guix lint -L <dir> -n <pkg>`. With `-n` (`--no-network`) it skips the checks that hit the network. Full lint is often rate-limited by GitHub. Report that, rather than treating it as a lint failure.
3. **Source:** `guix build -L <dir> -S <pkg>` proves that the URL and hash are right.

## Reading failures

- **Guile backtraces:** read from the **bottom**. The last frame plus the "In procedure …" or error line is what matters. Everything above it is call-stack noise from `guix/ui.scm`, `guix/store.scm` and similar.

  | Message | Usual cause |
  |---|---|
  | `Unbound variable: foo` | missing `#:use-module`, or a package variable renamed upstream |
  | `no code for module (x y)` | missing `-L`, or the module path doesn't match the file path |
  | `Wrong type argument … #f` in a phase | a label lookup (`assoc-ref inputs "name"`) found nothing, because the package was renamed |
  | `object not found` / `reference not found` during pull or reconfigure | a recorded channel commit no longer exists upstream (`guix-channels`) |
  | `hash mismatch` | wrong `sha256`, or upstream re-tagged. Re-verify the content, don't just copy the new hash. |

- **Build logs:** the error is usually near the end, but the cause may be earlier, at configure time: a feature not found, an option ignored, `Could NOT find X`. Grep the log for `error`, `not found`, `Could NOT`, `warning: unused`, `No such file`.
- **"Cannot find source file X"** when building a local checkout: X is probably a new file that `git-predicate` excluded because it isn't committed (`guix-local-development`).
- **Exit status 127** at run time means a command name was not found. Often the name differs on Guix, or the dependency is missing from `inputs`.

## Inspect a failed build tree

```sh
guix build -K <pkg>            # prints: note: keeping build directory `/tmp/guix-build-foo.drv-0'
cd /tmp/guix-build-foo.drv-0
source ./environment-variables # same PATH etc. as the builder
cd source && make              # or re-run the failing step by hand
```
Delete these trees when you're done. They can be large.

## Pre-seed a source when the network is slow

If you already have a checkout (a shallow clone, or one started in the background), add it to the store under the exact name and hash that the `git-fetch` origin expects. Guix then won't download it again:

```sh
rm -rf dir/.git                         # git-fetch checkouts contain no .git
guix hash -x -S nar dir                 # → base32 hash for the origin
guix repl -- scripts/add-checkout-to-store.scm <name>-<version>-checkout dir <base32>
guix build -L <dir> -S <pkg>            # should now be instant
```
The store name is what `(git-file-name name version)` yields: `<name>-<version>-checkout`. The script refuses if the resulting path doesn't match the expected hash. For tarballs, `guix download URL` already does this.

## Smoke-test the result

```sh
out=$(guix build -L <dir> <pkg>)
$out/bin/foo --version
env -i "$out/bin/foo" --version             # catches reliance on the user's PATH
guix shell --pure -L <dir> <pkg> -- foo --help
guix shell -C -L <dir> <pkg> -- foo --help  # container: no host files at all
```
- Check that version strings are real, not "0 (unknown)" or `@@VERSION@@`.
- `bin/foo` may be a wrapper. The real ELF is `bin/.foo-real`. Inspect it with `file`, `readelf -d` (RUNPATH) and `ldd`.
- For plugin and backend systems, run the program's own capability listing (`--list-devices`, `--version` showing enabled features) and check the configure log, so you know the features you expect were really built.
- For servers, start one on localhost, request a page, and stop it.
- Closure size and references: `guix size $out`, `guix gc --references $out`, `guix gc --requisites $out`.

## Other useful inspection

- `guix show <pkg>`: version, inputs, location. `guix edit <pkg>`: opens the recipe.
- `guix graph <pkg> | dot -Tpng > g.png` draws the dependency graph. `guix refresh -l <pkg>` lists what depends on it, to estimate rebuilds.
- `guix weather <pkg>` shows substitute availability. `guix challenge <pkg>` compares against substitute servers.
- `guix repl -L <dir>`, then `,use (my-channel packages foo)` and `(package-inputs foo)`, lets you poke at a package interactively.

## Reporting

State what was built, what was run, and what wasn't exercised. Don't call something working because it compiled. Don't claim lint is clean when network checks were skipped or rate-limited; say which.
