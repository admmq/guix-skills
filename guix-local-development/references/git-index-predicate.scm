;;; A local-file #:select? predicate based on Git's index.
;;;
;;; Guix's own 'git-predicate' (guix git-download) lists the files of the
;;; HEAD commit, so files that have been 'git add'ed but not committed are
;;; left out of the source and the build fails to find them.  This variant
;;; asks 'git ls-files' (the index), so 'git add' is enough.  File contents
;;; still come from disk, so uncommitted edits are included either way.
;;;
;;; Needs these modules in the enclosing file:
;;;   (ice-9 popen) (ice-9 textual-ports)
;;;
;;; Usage:
;;;   (define %source-dir (dirname (current-filename)))
;;;   (source (local-file %source-dir "foo-checkout"
;;;                       #:recursive? #t
;;;                       #:select? (or (git-index-predicate %source-dir)
;;;                                     (git-predicate %source-dir)
;;;                                     (const #t))))

(define (git-index-predicate directory)
  "Return a predicate that selects the files under DIRECTORY that are in Git's
index, and the directories that contain them, or #f if 'git ls-files' fails.
Unlike 'git-predicate', which lists the files of the last commit, this also
selects files that have been added but not committed yet."
  (false-if-exception
   (let* ((pipe   (open-pipe* OPEN_READ "git" "-C" directory "ls-files" "-z"))
          (files  (delete "" (string-split (get-string-all pipe) #\nul)))
          (names  (make-hash-table))
          (inodes (make-hash-table)))
     (define (add! name)
       (unless (or (string=? name ".") (hash-ref names name))
         (hash-set! names name #t)
         ;; Like 'git-predicate', compare inodes rather than file names, and
         ;; skip files that have been deleted from the working tree.
         (let ((stat (false-if-exception
                      (lstat (string-append directory "/" name)))))
           (when stat
             (hash-set! inodes (cons (stat:ino stat) (stat:dev stat)) #t)))
         (add! (dirname name))))
     (and (zero? (status:exit-val (close-pipe pipe)))
          (begin
            (for-each add! files)
            (lambda (file stat)
              (hash-ref inodes (cons (stat:ino stat) (stat:dev stat)) #f)))))))
