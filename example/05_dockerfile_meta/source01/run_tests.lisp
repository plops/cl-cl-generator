(eval-when (:compile-toplevel :execute :load-toplevel)
  (setf (readtable-case *readtable*) :invert))

(in-package :cl-dockerfile-generator)

(defparameter *test-failures* 0)

(defmacro assert-df (expected form)
  `(let ((actual (emit-df ',form)))
     (if (string= actual ,expected)
         (format t "PASS: ~s => ~s~%" ',form actual)
         (progn
           (incf *test-failures*)
           (format t "FAIL: ~s~%  Expected: ~s~%  Got:      ~s~%" ',form ,expected actual)))))

(defun run-all-tests ()
  (setf *test-failures* 0)
  
  ;; Test 1: Simple instructions and case-inversion
  (assert-df "FROM alpine:3.18" (from |ALPINE:3.18|))
  (assert-df "FROM alpine:3.18 AS base" (from |ALPINE:3.18| :as base))
  (assert-df "ARG DEBIAN_FRONTEND=noninteractive" (arg DEBIAN_FRONTEND noninteractive))
  (assert-df "ARG DEBIAN_FRONTEND" (arg DEBIAN_FRONTEND))

  ;; Test 2: ENV
  (assert-df "ENV MY_VAR=123" (env MY_VAR 123))
  (assert-df (format nil "ENV VAR1=val1 \\~%    VAR2=val2") (env VAR1 val1 VAR2 val2))

  ;; Test 3: RUN and pipes/seq/and
  (assert-df "RUN apt-get update" (run |APT-GET UPDATE|))
  (assert-df (format nil "RUN apt-get update \\~% && apt-get install -y curl")
             (run (and |APT-GET UPDATE| |APT-GET INSTALL -Y CURL|)))
  (assert-df (format nil "RUN apt-get update \\~%; apt-get install -y curl")
             (run (seq |APT-GET UPDATE| |APT-GET INSTALL -Y CURL|)))
  (assert-df "RUN cat a.txt | grep -i hello" (run (pipe |CAT A.TXT| |GREP -I HELLO|)))

  ;; Test 4: RUN raw strings (#r)
  (assert-df "RUN echo \"hello world\"" (run "echo \"hello world\""))
  (assert-df "RUN echo \"nested (parentheses)\"" (run "echo \"nested (parentheses)\""))
  (assert-df "RUN echo \"braces {and} brackets [nested]\"" (run "echo \"braces {and} brackets [nested]\""))
  (assert-df "RUN echo \"custom delimiter\"" (run "echo \"custom delimiter\""))

  ;; Test 5: COPY and ADD options
  (assert-df "COPY src dest" (copy src dest))
  (assert-df "COPY --from=builder src1 src2 dest" (copy src1 src2 dest :from builder))
  (assert-df "COPY --chown=root:root src dest" (copy src dest :chown |ROOT:ROOT|))
  (assert-df "COPY --from=builder --chown=root:root src dest" (copy src dest :from builder :chown |ROOT:ROOT|))
  (assert-df (format nil "COPY <<'EOF' dest~%hello world~%EOF") (copy :heredoc dest "hello world"))
  (assert-df "ADD http://example.com/file.tar.gz /dest" (add |HTTP://EXAMPLE.COM/FILE.TAR.GZ| /dest))
  (assert-df "ADD --chown=bin:bin http://example.com/file.tar.gz /dest" (add |HTTP://EXAMPLE.COM/FILE.TAR.GZ| /dest :chown |BIN:BIN|))

  ;; Test 6: EXPOSE, LABEL, ONBUILD, COMMENT, SHELL, STOPSIGNAL
  (assert-df "EXPOSE 80 443" (expose 80 443))
  (assert-df (format nil "LABEL maintainer=\"me\" \\~%      version=\"1.0\"")
             (label maintainer "me" version "1.0"))
  (assert-df "ONBUILD RUN echo \"onbuild trigger\"" (onbuild (run "echo \"onbuild trigger\"")))
  (assert-df "# this is a comment" (comment "this is a comment"))
  (assert-df "SHELL [\"/bin/bash\", \"-c\"]" (shell ("/bin/bash" "-c")))
  (assert-df "STOPSIGNAL SIGTERM" (stopsignal SIGTERM))

  ;; Test 7: CMD, ENTRYPOINT, VOLUME
  (assert-df "CMD [\"echo\", \"hello\"]" (cmd ("echo" "hello")))
  (assert-df "CMD echo hello" (cmd |ECHO HELLO|))
  (assert-df "ENTRYPOINT [\"/bin/bash\", \"-c\"]" (entrypoint ("/bin/bash" "-c")))
  (assert-df "ENTRYPOINT /bin/bash" (entrypoint |/BIN/BASH|))
  (assert-df "VOLUME [\"/data\"]" (volume ("/data")))
  (assert-df "VOLUME /data" (volume |/DATA|))

  ;; Test 8: HEALTHCHECK
  (assert-df "HEALTHCHECK --interval=5s --timeout=3s --retries=3 CMD [\"curl\", \"-f\", \"http://localhost/\"]"
             (healthcheck (CMD ("curl" "-f" "http://localhost/")) :interval 5s :timeout 3s :retries 3))
  (assert-df "HEALTHCHECK --start-period=10s NONE"
             (healthcheck NONE :start-period 10s))

  ;; Test 9: Newly introduced features and refactoring improvements
  (assert-df (format nil "RUN --mount=a --mount=b command") (run :mount ("a" "b") |COMMAND|))
  (assert-df (format nil "RUN --mount=a command") (run :mount "a" |COMMAND|))
  (assert-df (format nil "RUN <<'EOF'~%command~%EOF") (run :heredoc "command"))
  (assert-df (format nil "FROM alpine:3.18~%RUN command~%") (toplevel (from |ALPINE:3.18|) (run |COMMAND|)))
  (assert-df "COPY --from=stage --chown=owner --link --chmod=755 --parents --exclude=*.log src dest"
             (copy src dest :from stage :chown owner :link t :chmod 755 :parents t :exclude "*.log"))
  (assert-df "ADD --chown=owner --link --chmod=755 --checksum=sha256:123 src dest"
             (add src dest :chown owner :link t :chmod 755 :checksum "sha256:123"))

  ;; Test 10: Error handling and warnings
  (let ((warned nil))
    (handler-bind ((warning (lambda (w)
                              (declare (ignore w))
                              (setf warned t)
                              (muffle-warning))))
      (emit-df '(runn |something|)))
    (if warned
        (format t "PASS: (runn ...) signaled warning~%")
        (progn
          (incf *test-failures*)
          (format t "FAIL: (runn ...) did not signal warning~%"))))

  (let ((errored nil))
    (handler-case (emit-df '(copy src dest :from))
      (error (e)
        (declare (ignore e))
        (setf errored t)))
    (if errored
        (format t "PASS: (copy src dest :from) threw error as expected~%")
        (progn
          (incf *test-failures*)
          (format t "FAIL: (copy src dest :from) did not throw error~%"))))

  (format t "~%Test results: ~a failures.~%" *test-failures*)
  (if (> *test-failures* 0)
      (sb-ext:exit :code 1)
      (sb-ext:exit :code 0)))
