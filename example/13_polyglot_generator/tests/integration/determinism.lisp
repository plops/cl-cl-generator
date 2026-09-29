;;;; determinism.lisp --- generate twice: byte identical files, second run
;;;; reports :unchanged and keeps the modification times (R9, E15)

(in-package :polyglot.integration)

(defun file-digests (results)
  (loop for (path) in results
        collect (cons path (list (uiop:read-file-string path :external-format :utf-8)
                                 (file-write-date path)))))

(defun run-determinism (programs targets)
  (let ((failures 0) (files 0))
    (dolist (program programs)
      (multiple-value-bind (project file) (load-program program)
        (let* ((out (merge-pathnames (format nil "_determinism/~a/" program) (build-dir)))
               (targets (remove-if-not #'backend-available-p targets)))
          (uiop:delete-directory-tree out :validate t :if-does-not-exist :ignore)
          (handler-bind ((warning #'muffle-warning))
            (let* ((first (polyglot:write-project project :targets targets :out out :source-file file))
                   (before (file-digests first)))
              (sleep 1.1)
              (let* ((second (polyglot:write-project project :targets targets :out out :source-file file))
                     (after (file-digests second)))
                (incf files (length first))
                (loop for (path . status) in second
                      for (nil text1 time1) in before
                      for (nil text2 time2) in after
                      unless (and (eq status :unchanged) (string= text1 text2) (= time1 time2))
                      do (incf failures)
                      (format t "~&NOT DETERMINISTIC: ~a (~a)~%" path status))
                ;; a fresh generation into another directory is byte identical
                (let* ((out2 (merge-pathnames (format nil "_determinism2/~a/" program) (build-dir)))
                       (third (polyglot:write-project project :targets targets :out out2 :source-file file)))
                  (loop for (p1) in first
                        for (p2) in third
                        unless (equal (uiop:read-file-string p1) (uiop:read-file-string p2))
                        do (incf failures)
                        (format t "~&DIFFERENT BYTES: ~a vs ~a~%" p1 p2))
                  (uiop:delete-directory-tree out2 :validate t :if-does-not-exist :ignore))))))))
    (format t "~&determinism: ~d files checked, ~d problems~%" files failures)
    (if (zerop failures) 0 1)))
