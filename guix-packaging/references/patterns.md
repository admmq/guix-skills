# Packaging patterns (copy, then adapt)

Each snippet goes inside a package's `arguments` (`#:phases` …) unless noted otherwise. All of them use current gexp style.

## Put all inputs on PATH for a shell script, without renaming it

Use this when a script calls many external commands and `wrap-program` would break it (for example, the script derives its name from `$0`). It survives upstream edits better than substituting each command.
```scheme
(add-after 'unpack 'patch-script
  (lambda _
    (substitute* "bin/tool"
      (("@@VERSION@@") #$version)
      (("^#!/usr/bin/env bash" shebang)
       (string-append
        shebang "\n"
        "export PATH=\""
        (string-join
         (search-path-as-list
          '("bin" "sbin")
          (list #$@(map cadr (package-inputs this-package))))
         ":")
        "${PATH:+:$PATH}\"")))))
```
`package-inputs` returns labeled entries `("name" pkg)`, so `cadr` takes the package. Every command the script calls must come from `inputs`. Grep the script for them, including `tput`, `awk`, `find`, `grep`, `wget`, `partprobe` (parted) and so on.

## Substitute commands with absolute store paths

```scheme
(add-after 'install 'patch-launcher
  (lambda* (#:key inputs #:allow-other-keys)
    (substitute* (string-append #$output "/lib/app/bin/app")
      (("\\$\\(which ")  (string-append "$(" (search-input-file inputs "bin/which") " "))
      (("(if|\\|) grep " _ prefix)
       (string-append prefix " " (search-input-file inputs "bin/grep") " ")))))
```

## Extra source (submodule or vendored dependency) as its own origin

```scheme
(define foo-submodule-source
  ;; Pinned by upstream's third_party/bar submodule.
  (let ((commit "<sha>") (revision "1"))
    (origin
      (method git-fetch)
      (uri (git-reference (url "https://example.org/bar") (commit commit)))
      (file-name (git-file-name "bar" (git-version "1.0" revision commit)))
      (sha256 (base32 "…")))))

;; in #:phases
(add-after 'unpack 'unpack-submodules
  (lambda _
    (delete-file-recursively "third_party/bar")
    (copy-recursively #$foo-submodule-source "third_party/bar")))
```

## Prebuilt asset (such as a web UI) as a native input, referenced by file name

```scheme
(native-inputs
 (list (origin
         (method url-fetch)
         (uri "https://example.org/releases/download/b123/app-b123-ui.tar.gz")
         (sha256 (base32 "…")))))
;; in #:phases
(add-after 'unpack 'unpack-ui
  (lambda _
    (mkdir-p "ui/dist")
    (invoke "tar" "-xf" #$(this-package-native-input "app-b123-ui.tar.gz")
            "-C" "ui/dist" "--strip-components=1")))
```

## Version metadata that upstream normally reads from git

```scheme
(let ((build "<N>") (commit "<short sha>"))   ; what the release tag points to
  (package
    …
    (arguments
     (list #:configure-flags
           #~(list #$(string-append "-DAPP_BUILD_NUMBER=" build)
                   #$(string-append "-DAPP_BUILD_COMMIT=" commit))))))
```

## Remove a dependency manager (conan, FetchContent) from CMake

```scheme
(add-after 'unpack 'remove-conan
  (lambda _
    (substitute* "CMakeLists.txt"
      ((".*conan_provider\\.cmake.*") "")
      (("cmake_minimum_required\\(VERSION ([0-9.]+)\\)" all)
       (string-append all "\nlist(PREPEND CMAKE_MODULE_PATH "
                      "\"${CMAKE_SOURCE_DIR}/cmake/Modules\")")))))
```
If upstream lacks `Find*.cmake` modules for system libraries, ship them in a patch. In a channel: `(patches (search-patches "my-channel/patches/foo-find-modules.patch"))`. The path is resolved relative to the load path, so it's relative to the channel's module root.

## Fence off a block of upstream CMake

```scheme
(substitute* "CMakeLists.txt"
  (("qt_generate_deploy_app_script\\(") "if(FALSE)\nqt_generate_deploy_app_script(")
  (("# install drivers") "endif() # GUIX: skip deploy script\n# install drivers"))
```
Check afterwards that both substitutions applied, because `substitute*` doesn't fail when nothing matches.

## Let CMake's runtime-dependency filters accept store paths

```scheme
(substitute* "CMakeLists.txt"
  (("(\\[\\[\\^/usr/lib\\.\\*\\]\\])" all)
   (string-append all "\n        [[^/gnu/store/.*]]")))
```

## Move desktop integration installed into the prefix root

```scheme
(add-after 'install 'install-desktop-entry
  (lambda _
    (let ((apps  (string-append #$output "/share/applications"))
          (icons (string-append #$output "/share/icons/hicolor/512x512/apps")))
      (with-directory-excursion #$output
        (substitute* "App.desktop"
          (("^Exec=.*") (string-append "Exec=" #$output "/bin/App\n"))
          (("^Icon=.*") "Icon=App\n"))
        (mkdir-p apps) (mkdir-p icons)
        (rename-file "App.desktop" (string-append apps "/App.desktop"))
        (rename-file "App.png" (string-append icons "/App.png"))
        (for-each delete-file '("App.service" "post_install.sh"))))))
```

## Undo qt-wrap on data files that live in bin/

```scheme
(add-after 'qt-wrap 'unwrap-data-files
  (lambda _
    (let ((bin (string-append #$output "/bin")))
      (for-each (lambda (name)
                  (let ((wrapped (string-append bin "/" name))
                        (real    (string-append bin "/." name "-real")))
                    (when (file-exists? real)
                      (delete-file wrapped)
                      (rename-file real wrapped))))
                '("data1.dat" "data2.dat")))))
```

## Variant that sets environment variables before configure

```scheme
(arguments
 (substitute-keyword-arguments (package-arguments base)
   ((#:phases phases)
    #~(modify-phases #$phases
        (add-before 'configure 'set-build-env
          (lambda _
            (for-each (lambda (pair) (apply setenv pair))
                      '#$%build-environment)))))))   ; a list of ("VAR" "value")
```
To pass a multi-line value through CMake `-D` into a C string literal, join the lines with a literal `\\n` in Scheme.

## Data-only package from several downloaded files

```scheme
(package
  (name "foo-data") (version %foo-data-version)
  (source foo-data-a)                     ; any one of the origins
  (build-system trivial-build-system)
  (arguments
   (list #:modules '((guix build utils))
         #:builder
         #~(begin
             (use-modules (guix build utils))
             (let ((share (string-append #$output "/share/foo-data")))
               (mkdir-p share)
               (copy-file #$foo-data-a (string-append share "/a.dat"))
               (copy-file #$foo-data-b (string-append share "/b.dat")))))))
  …)
```

## Custom kernel from a different upstream source

```scheme
(package
  (inherit (customize-linux #:linux linux-6.18))   ; base kernel package
  (name "my-linux")
  (version "6.18")
  (source (origin (method git-fetch)
                  (uri (git-reference (url "https://git.kernel.org/…/linux.git")
                                      (commit (string-append "v" version))))
                  (file-name (git-file-name name version))
                  (sha256 (base32 "…")))))
```
`customize-linux` lives in `(gnu packages linux)`. Its keywords are `#:name`, `#:linux`, `#:source`, `#:defconfig`, `#:modconfig`, `#:configs` (extra `CONFIG_…` lines) and `#:extra-version`. The base package can come from another channel, for example a non-libre kernel variant. Keep the version of the base and of the source consistent, because the kernel config is chosen by version.
