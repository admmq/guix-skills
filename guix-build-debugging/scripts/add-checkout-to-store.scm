;; Usage: guix repl -- add-checkout-to-store.scm NAME DIR BASE32-HASH
;;
;; Add DIR to the store as NAME, hashed recursively with SHA-256 (the "nar"
;; serialization).  That is the same store path a fixed-output origin -- for
;; instance a git-fetch origin whose file-name is NAME and whose sha256 is
;; BASE32-HASH -- produces, so Guix will not download that source again.
;;
;; DIR must look exactly like the fetched source: for git-fetch, no .git
;; directory, and submodules present only if the origin is recursive.
;; Compute the hash first with:  guix hash -x -S nar DIR
;;
;; Exits non-zero, and says MISMATCH, if the content does not produce the
;; expected store path.

(use-modules (guix store)
             (guix base32)
             (ice-9 match))

(match (command-line)
  ((_ name dir expected)
   (let ((expected-path (fixed-output-path
                         name (nix-base32-string->bytevector expected)
                         #:hash-algo 'sha256
                         #:recursive? #t)))
     (with-store store
       (let ((added (add-to-store store name #t "sha256" dir)))
         (format #t "expected: ~a~%added:    ~a~%" expected-path added)
         (unless (string=? added expected-path)
           (display "MISMATCH\n")
           (exit 1))))))
  (_
   (display "usage: guix repl -- add-checkout-to-store.scm NAME DIR BASE32-HASH\n"
            (current-error-port))
   (exit 2)))
