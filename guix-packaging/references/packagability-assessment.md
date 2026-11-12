# Can X be packaged for Guix? How to assess it

Answer from evidence gathered on the real source tree and the user's real Guix, not from general impressions. Give a verdict per component (CLI, library, desktop app), list concrete blockers, and say clearly that it's an assessment, not a tested build.

## 0. Maybe it's already there, or something equivalent is

- Run `guix search <name>` and `guix show <name>` across all configured channels (`guix describe` lists them).
- If the user's goal is a capability ("an AI coding agent", "a VPN client"), search package descriptions for alternatives that are already packaged, and check which of them have substitutes (`guix weather <pkg>`). Something that installs today usually beats a new packaging project.

## 1. Toolchain

- Compare upstream's minimum compiler or runtime version with what Guix has: `guix show rust go node python gcc-toolchain`.
- Toolchain pin files that Guix doesn't use (`rust-toolchain.toml`, `.nvmrc`, `.python-version`) don't matter. The minimum declared in the build manifest (`rust-version`, `go` directive) does.

## 2. Dependencies

Run the importer and see how much already exists:

| Ecosystem | Importer |
|---|---|
| Rust | `guix import crate -f Cargo.lock <name>` |
| Go | `guix import go -r <module>@<version>` |
| Python | `guix import pypi <name>` |
| Emacs | `guix import elpa <name>` |
| npm | `guix import npm-binary <name>` |
| CRAN, hackage, gem, … | `guix import --help` lists them |

Report the counts, for example "907 of 1,113 crates already in Guix; 206 new".

Watch for:
- **Git dependencies pinned to commits no longer on any branch.** Importers fail with "object not found". The SHA may still be fetchable with plain `git`, but it can disappear.
- **Vendored C or C++ libraries** inside language packages: OpenSSL (`openssl-src`), libdbus, llama.cpp, AWS-LC, sqlite, zstd, oniguruma. Guix wants system copies. Note which can be pointed at system libraries, and which can be avoided by disabling a feature.

## 3. Feature flags

- Find the feature set upstream uses for portable or distro builds, such as CI's musl or "portable" profile. It often drops self-updaters, the system keyring, GPU and local-inference backends. Those are exactly the parts that are hard on Guix.
- A distro package must not self-update. Disable the updater feature.

## 4. Build-time network and environment

- Any download during the build (npm install, model files, prebuilt UIs) needs replacing.
- Tests need a temporary HOME and XDG dirs and no network. Expect to skip some.
- An existing Nix flake or other distro recipe is a good map of the native dependencies and the test setup.

## 5. Desktop and Electron apps

- Electron apps pin an exact Electron major version. Check `guix show electron` for which versions Guix has. A mismatch usually makes a from-source package unrealistic in Guix proper.
- The practical routes are repackaging upstream's prebuilt binary in a personal or non-free channel (`guix-foreign-binaries`), or running it in `guix shell -CF`.

## 6. Licence

- Free licence: it can go into Guix proper (after unbundling).
- Non-free or unclear: it belongs in a personal or non-free channel only.

## Output shape

```
CLI: doable, with N fixes.
  Works already: toolchain (Guix X ≥ required Y), N/M deps present, reference recipe in flake.nix.
  Needs work: 1) git dep pinned to orphaned commit …  2) vendored OpenSSL via feature `vendored` …
Desktop app: not realistic for Guix proper (pins Electron N; Guix has M).
Alternatives already packaged: …
Not verified: no build attempted.
```
