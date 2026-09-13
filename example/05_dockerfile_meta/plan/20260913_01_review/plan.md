

### Teil 1: Antworten auf 1A & 1C

#### Warum funktioniert `apt-get install` bei dir (1A) und wie loggt man es in `setup01.sh`?
* **Warum es geklappt hat**: Du nutzt BuildKit Cache-Mounts:
  `--mount=type=cache,target=/var/lib/apt/lists,sharing=locked`
  BuildKit speichert den Inhalt dieses Verzeichnisses auf deinem Host über Builds hinweg. Wenn du einmal in der Vergangenheit `apt-get update` ausgeführt hast (oder ein anderes Dockerfile auf derselben Maschine diesen Cache befüllt hat), bleiben die Paketindizes im Cache erhalten. Erst wenn der Cache mit `docker builder prune -a` gelöscht wird, schlägt ein Build ohne `apt-get update` fehl.
* **Änderung in `setup01.sh` zum Überprüfen & Loggen**:
  Führe den Build mit vollständiger Log-Ausgabe aus und lass dir vor der Installation den Inhalt von `/var/lib/apt/lists` ausgeben:

```bash
#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="build_$(date +%Y%m%d_%H%M%S).log"
echo "Starte Docker Build. Logge nach: $LOG_FILE"

# Build ausführen und ungekürzten BuildKit-Output mitschneiden:
DOCKER_BUILDKIT=1 docker build \
  --progress=plain \
  --no-cache \
  -t ai-env:latest \
  -f Dockerfile . 2>&1 | tee "$LOG_FILE"

echo "Build abgeschlossen. Suche nach apt-Fehlern oder Paketlisten im Log:"
grep -E "(Reading package lists|Unable to locate package|Get:[0-9]+)" "$LOG_FILE" || true
```

Um im Dockerfile selbst zu sehen, was `apt` vorfindet, kannst du testweise ganz oben im Runner einfügen:
```lisp
(run :mount "type=cache,target=/var/lib/apt/lists,sharing=locked"
     "ls -la /var/lib/apt/lists/")
```

---

#### Zu 1C: Warum ging der Build trotz `:mount` mit Listen?
Der Code, den du im zweiten Snippet gepostet hast, enthielt bereits folgende Korrektur:
```lisp
((eq (first args) :mount)
 (let ((mount-spec (second args))
       (cmd (emit-df (caddr args))))
   (if (listp mount-spec)
       (format nil "RUN ~{--mount=~a~^ ~} ~a" (mapcar #'emit-val mount-spec) cmd)
       (format nil "RUN --mount=~a ~a" (emit-val mount-spec) cmd))))
```
In deiner aktiven `dock.lisp` war das Listen-Handling also bereits aktiv – nur in der älteren `gen.lisp` aus dem ersten Paste fehlte es noch.

---

### Teil 2: Update von `gen.lisp` (DSL-Meta-Generator)

Wir behalten den Meta-Generator-Ansatz bei, setzen aber **2B** um:
1. `emit-df` wandelt `(car code)` in ein Keyword um: `(intern (string-upcase (symbol-name (car code))) :keyword)`. Dadurch ist es völlig egal, aus welchem Package (`:cl`, `:cl-dockerfile-generator`, `:keyword`) die S-Expression stammt.
2. Der `case`-Ausdruck matcht jetzt sauber auf Keywords (`:FROM`, `:RUN`, `:COPY` etc.).
3. Im `t`-Fall wird eine Warnung emittiert, falls eine unbekannte Instruktion auftaucht.
4. Alle Optionen für `COPY` und `ADD` (`:link`, `:chmod`, `:parents`, `:exclude`, `:checksum`) sowie Listen bei `:mount` sind fest integriert.

Hier ist die aktualisierte `gen.lisp`:

```lisp
;; gen.lisp
(eval-when (:compile-toplevel :execute :load-toplevel)
  (let ((current-dir (make-pathname :directory (pathname-directory *load-pathname*))))
    (push (merge-pathnames "../../" current-dir) asdf:*central-registry*))
  (ql:quickload :cl-cl-generator))

(defpackage :cl-dockerfile-generator/meta
  (:use :cl :cl-cl-generator)
  (:documentation "Package for the meta-generator that constructs the Dockerfile generator."))

(in-package :cl-dockerfile-generator/meta)

(let* ((output-dir (asdf:system-relative-pathname :cl-cl-generator "example/05_dockerfile_meta/source01/"))
       (output-filename "dock")
       (code
         `(toplevel
            (defpackage :cl-dockerfile-generator
              (:use :cl)
              (:export :emit-df :write-df)
              (:documentation "Main package for the generated cl-dockerfile-generator library."))
            (in-package :cl-dockerfile-generator)

            (eval-when (:compile-toplevel :execute :load-toplevel)
              (setf (readtable-case *readtable*) :invert)
              (defun read-balanced (stream open-char close-char)
                (with-output-to-string (out)
                  (loop with depth = 1
                        for c = (read-char stream t nil t)
                        do (cond
                             ((char= c open-char) (incf depth) (write-char c out))
                             ((char= c close-char) (decf depth)
                              (if (zerop depth) (loop-finish) (write-char c out)))
                             (t (write-char c out))))))
              (set-dispatch-macro-character #\# #\r
                (lambda (stream char arg)
                  (declare (ignore char arg))
                  (let ((delimiter (read-char stream t nil t)))
                    (cond
                      ((char= delimiter #\() (read-balanced stream #\( #\)))
                      ((char= delimiter #\[) (read-balanced stream #\[ #\]))
                      ((char= delimiter #\{) (read-balanced stream #\{ #\}))
                      (t
                       (with-output-to-string (out)
                         (loop for c = (read-char stream t nil t)
                               until (char= c delimiter)
                               do (write-char c out)))))))))

            (declaim (ftype (function (t) string) emit-df))

            (defun emit-val (x)
              (cond
                ((stringp x) x)
                ((listp x) (emit-df x))
                (t (format nil "~a" x))))

            (defun parse-copy-add-args (args allowed-options)
              (let (paths plist (lst args))
                (loop while lst
                      do (if (and (keywordp (car lst)) (member (car lst) allowed-options))
                             (progn
                               (unless (cdr lst)
                                 (error "Keyword option ~a requires a value" (car lst)))
                               (setf (getf plist (car lst)) (cadr lst))
                               (setf lst (cddr lst)))
                             (progn
                               (push (car lst) paths)
                               (setf lst (cdr lst)))))
                (values (nreverse paths) plist)))

            (defun emit-json-or-shell (keyword val)
              (if (listp val)
                  (format nil "~a [~{~s~^, ~}]" keyword (mapcar #'emit-val val))
                  (format nil "~a ~a" keyword (emit-val val))))

            (defun emit-df (code)
              (cond
                ((null code) "")
                ((listp code)
                 (let ((op (and (symbolp (car code))
                                (intern (string-upcase (symbol-name (car code))) :keyword))))
                   (case op
                     (:toplevel
                      (with-output-to-string (s)
                        (loop for form in (cdr code)
                              do (format s "~a~%" (emit-df form)))))
                     (:directive
                      (destructuring-bind (name val) (cdr code)
                        (format nil "# ~a=~a" (emit-val name) (emit-val val))))
                     (:from
                      (destructuring-bind (image &key as) (cdr code)
                        (if as
                            (format nil "FROM ~a AS ~a" (emit-val image) (emit-val as))
                            (format nil "FROM ~a" (emit-val image)))))
                     (:arg
                      (destructuring-bind (name &optional val) (cdr code)
                        (if val
                            (format nil "ARG ~a=~a" (emit-val name) (emit-val val))
                            (format nil "ARG ~a" (emit-val name)))))
                     (:env
                      (let ((args (cdr code)))
                        (format nil "ENV ~{~a=~a~^ \\~%    ~}"
                                (loop for (k v) on args by #'cddr
                                      collect (emit-val k) collect (emit-val v)))))
                     (:run
                      (let ((args (cdr code)))
                        (cond
                          ((eq (first args) :heredoc)
                           (format nil "RUN <<'EOF'~%~a~%EOF" (emit-val (second args))))
                          ((eq (first args) :mount)
                           (let ((mount-spec (second args))
                                 (cmd (emit-df (caddr args))))
                             (if (listp mount-spec)
                                 (format nil "RUN ~{--mount=~a~^ ~} ~a" (mapcar #'emit-val mount-spec) cmd)
                                 (format nil "RUN --mount=~a ~a" (emit-val mount-spec) cmd))))
                          (t (format nil "RUN ~a" (emit-df (first args)))))))
                     (:and
                      (format nil "~{~a~^ \\~% && ~}" (mapcar #'emit-df (cdr code))))
                     (:seq
                      (format nil "~{~a~^ \\~%; ~}" (mapcar #'emit-df (cdr code))))
                     (:pipe
                      (format nil "~{~a~^ | ~}" (mapcar #'emit-df (cdr code))))
                     (:copy
                      (let ((args (cdr code)))
                        (if (eq (first args) :heredoc)
                            (destructuring-bind (dest content) (cdr args)
                              (format nil "COPY <<'EOF' ~a~%~a~%EOF" (emit-val dest) (emit-val content)))
                            (multiple-value-bind (paths options)
                                (parse-copy-add-args args '(:from :chown :link :chmod :parents :exclude))
                              (let ((dest (car (last paths)))
                                    (srcs (butlast paths))
                                    (from (getf options :from))
                                    (chown (getf options :chown))
                                    (link (getf options :link))
                                    (chmod (getf options :chmod))
                                    (parents (getf options :parents))
                                    (exclude (getf options :exclude)))
                                (format nil "COPY~@[ --from=~a~]~@[ --chown=~a~]~:[~; --link~]~@[ --chmod=~a~]~:[~; --parents~]~@[ --exclude=~a~] ~{~a~^ ~} ~a"
                                        (and from (emit-val from))
                                        (and chown (emit-val chown))
                                        link
                                        (and chmod (emit-val chmod))
                                        parents
                                        (and exclude (emit-val exclude))
                                        (mapcar #'emit-val srcs)
                                        (emit-val dest)))))))
                     (:add
                      (let ((args (cdr code)))
                        (multiple-value-bind (paths options)
                            (parse-copy-add-args args '(:chown :link :chmod :checksum))
                          (let ((dest (car (last paths)))
                                (srcs (butlast paths))
                                (chown (getf options :chown))
                                (link (getf options :link))
                                (chmod (getf options :chmod))
                                (checksum (getf options :checksum)))
                            (format nil "ADD~@[ --chown=~a~]~:[~; --link~]~@[ --chmod=~a~]~@[ --checksum=~a~] ~{~a~^ ~} ~a"
                                    (and chown (emit-val chown))
                                    link
                                    (and chmod (emit-val chmod))
                                    (and checksum (emit-val checksum))
                                    (mapcar #'emit-val srcs)
                                    (emit-val dest))))))
                     (:expose
                      (format nil "EXPOSE ~{~a~^ ~}" (mapcar #'emit-val (cdr code))))
                     (:label
                      (format nil "LABEL ~{~a=~s~^ \\~%      ~}"
                              (loop for (k v) on (cdr code) by #'cddr
                                    collect (emit-val k) collect (emit-val v))))
                     (:onbuild
                      (format nil "ONBUILD ~a" (emit-df (second code))))
                     (:comment
                      (format nil "# ~a" (emit-val (second code))))
                     (:shell
                      (format nil "SHELL [~{~s~^, ~}]" (mapcar #'emit-val (second code))))
                     (:stopsignal
                      (format nil "STOPSIGNAL ~a" (emit-val (second code))))
                     (:healthcheck
                      (let ((args (cdr code)))
                        (multiple-value-bind (cmds options)
                            (parse-copy-add-args args '(:interval :timeout :start-period :retries))
                          (let ((cmd (car cmds))
                                (interval (getf options :interval))
                                (timeout (getf options :timeout))
                                (start-period (getf options :start-period))
                                (retries (getf options :retries)))
                            (format nil "HEALTHCHECK~@[ --interval=~a~]~@[ --timeout=~a~]~@[ --start-period=~a~]~@[ --retries=~a~] ~a"
                                    (and interval (emit-val interval))
                                    (and timeout (emit-val timeout))
                                    (and start-period (emit-val start-period))
                                    (and retries (emit-val retries))
                                    (if (listp cmd)
                                        (let ((val (second cmd)))
                                          (if (listp val)
                                              (format nil "~a [~{~s~^, ~}]" (emit-val (first cmd)) (mapcar #'emit-val val))
                                              (format nil "~a ~a" (emit-val (first cmd)) (emit-val val))))
                                        (emit-val cmd)))))))
                     (:cmd (emit-json-or-shell "CMD" (second code)))
                     (:entrypoint (emit-json-or-shell "ENTRYPOINT" (second code)))
                     (:volume (emit-json-or-shell "VOLUME" (second code)))
                     (:workdir (format nil "WORKDIR ~a" (emit-val (second code))))
                     (:user (format nil "USER ~a" (emit-val (second code))))
                     (t
                      (let ((instruction (emit-val (car code))))
                        (unless (member (string-upcase instruction)
                                        '("FROM" "RUN" "COPY" "ADD" "ENV" "ARG" "EXPOSE"
                                          "LABEL" "CMD" "ENTRYPOINT" "VOLUME" "WORKDIR"
                                          "USER" "ONBUILD" "STOPSIGNAL" "HEALTHCHECK"
                                          "SHELL" "MAINTAINER")
                                        :test #'string=)
                          (warn "Unknown Dockerfile instruction: ~a" instruction))
                        (format nil "~a ~{~a~^ ~}" instruction (mapcar #'emit-val (cdr code)))))))))
                (t (emit-val code))))

            (defun file-contents-equal-p (filename content)
              (and (probe-file filename)
                   (with-open-file (stream filename :direction :input :if-does-not-exist nil)
                     (when stream
                       (let ((file-content (make-string (file-length stream))))
                         (read-sequence file-content stream)
                         (string= content file-content))))))

            (defun write-df (filename code &optional ignore-hash)
              (let ((code-str (emit-df code)))
                (when (or ignore-hash (not (file-contents-equal-p filename code-str)))
                  (ensure-directories-exist filename)
                  (with-open-file (stream filename :direction :output :if-exists :supersede :if-does-not-exist :create)
                    (write-sequence code-str stream)))
                filename)))))
  (let ((result-path (write-source output-filename code output-dir)))
    (format t "Successfully generated cl-dockerfile-generator at ~a~%" result-path)))
```

---

### Teil 3: Updates in `gen_ai_env.lisp`

Hier sind alle Anpassungen eingearbeitet:
1. **2D**: Konsequente Verwendung von `#r|...|` für alle Shell-Skripte und Strings.
2. **3A**: Paket-Deduplizierung in `*ubuntu-packages*` und `runner-stage` via `(remove-duplicates ... :test #'string=)`.
3. **3B**: Devin-CLI-Installation bleibt unangetastet mit `|| true`.
4. **3C**: Radikal vereinfachte Wrapper-Skripte (direktes `exec binary <flag> "$@"`).
5. **3E**: Das `(volume ...)`-Statement im Runner wurde entfernt (wird in `setup02_run.sh` ausgelagert).

Auszug der überarbeiteten Stellen in `gen_ai_env.lisp`:

#### Bereinigte Paketlisten (3A):
```lisp
(defparameter *ubuntu-packages*
  (remove-duplicates
   '("less"
     "file"
     "findutils"
     "tree"
     "man-db"
     "procps"
     "psmisc"
     "iproute2"
     "iputils-ping"
     "dnsutils"
     "ripgrep"
     "fd-find"
     "yq"
     "picocom"
     "cmake"
     "build-essential"
     "git"
     "pkg-config"
     "usbutils"
     "libusb-1.0-0-dev"
     "lsof"
     "strace"
     "moreutils"
     "tmux"
     "shellcheck"
     "fzf"
     "clang-format"
     "clang-tidy"
     "clangd"
     "ninja-build"
     "bat"
     "git-lfs"
     "openssh-client"
     "dos2unix"
     "parallel"
     "unzip"
     "zip"
     "xz-utils"
     "rsync")
   :test #'string=))
```

#### Radikal vereinfachte Wrapper-Skripte (3C):
```lisp
(defun agent-wrapper-script (real-binary default-flag)
  (format nil "#!/usr/bin/env bash~%set -euo pipefail~%exec ~a ~a \"$@\"~%"
          real-binary default-flag))

(defun kiro-wrapper-script (real-binary)
  (format nil "#!/usr/bin/env bash~%set -euo pipefail~%exec ~a chat --v3 --trust-all-tools \"$@\"~%"
          real-binary))

(defun grok-wrapper-script (real-binary)
  (format nil "#!/usr/bin/env bash~%set -euo pipefail~%exec ~a --always-approve \"$@\"~%"
          real-binary))

(defun muse-wrapper-script (real-binary)
  (format nil "#!/usr/bin/env bash~%set -euo pipefail~%exec ~a --yolo \"$@\"~%"
          real-binary))

(defun devin-wrapper-script (real-binary)
  (format nil "#!/usr/bin/env bash~%set -euo pipefail~%exec ~a --permission-mode bypass \"$@\"~%"
          real-binary))
```

#### Smoke-Tests mit `#r|...|` (2D):
```lisp
(defparameter *smoke-tests*
  `((*install-codex*
     "Codex by running the CLI and asserting it matches the latest npm release"
     #r|set -eu
codex --version > /tmp/codex-version.txt
grep -Eq '[0-9]+\.[0-9]+\.[0-9]+' /tmp/codex-version.txt
installed_version="$(node -p "require(require('path').join(process.argv[1], '@openai/codex/package.json')).version" "$(npm root -g)" | tr -d '[:space:]')"
latest_version="$(npm view @openai/codex version | tr -d '[:space:]')"
[ -n "$installed_version" ]
[ "$installed_version" = "$latest_version" ]
|)
    (*install-kiro-cli* "kiro-cli by invoking the wrapped CLI and helpers"
                        #r|set -eu
kiro-cli --help > /tmp/kiro-cli-help.txt
[ -s /tmp/kiro-cli-help.txt ]
grep -qi "kiro" /tmp/kiro-cli-help.txt

kiro-cli-chat --help > /tmp/kiro-cli-chat-help.txt
[ -s /tmp/kiro-cli-chat-help.txt ]
grep -qi "kiro" /tmp/kiro-cli-chat-help.txt

kiro-cli-term --help > /tmp/kiro-cli-term-help.txt
[ -s /tmp/kiro-cli-term-help.txt ]
grep -qi "kiro" /tmp/kiro-cli-term-help.txt
|)
    (*install-grok* "Grok Build by checking the CLI version"
                    #r|set -eu
grok --version
agent --version
|)
    (*install-muse*
     "Meta Muse Code by checking the CLI version"
     #r|set -eu
muse --version > /tmp/muse-version.txt
[ -s /tmp/muse-version.txt ]
grep -Eq '[0-9]+\.[0-9]+\.[0-9]+-R[0-9]+' /tmp/muse-version.txt
|)
    (*install-azure-cli* "Azure CLI by checking the installed version"
                         #r|set -eu
az version > /tmp/az-version.json
grep -q '"azure-cli"' /tmp/az-version.json
|)
    (*install-docker-cli* "Docker CLI and Buildx by checking their client versions"
                          #r|set -eu
docker --version > /tmp/docker-version.txt
grep -Eq 'Docker version [0-9]+\.[0-9]+' /tmp/docker-version.txt
docker buildx version > /tmp/docker-buildx-version.txt
grep -Eq 'github\.com/docker/buildx v[0-9]+\.[0-9]+' /tmp/docker-buildx-version.txt
|)
    (*install-arm-none-eabi*
     "Arm GNU bare-metal toolchain by compiling a Cortex-M7 object"
     #r|set -eu
tmpdir="$(mktemp -d /tmp/ai-env-arm-none-eabi.XXXXXX)"
cat > "$tmpdir/test.c" <<'C_EOF'
void Reset_Handler(void) {}
C_EOF
arm-none-eabi-gcc -mcpu=cortex-m7 -mthumb -ffreestanding -c "$tmpdir/test.c" -o "$tmpdir/test.o"
arm-none-eabi-readelf -h "$tmpdir/test.o" > "$tmpdir/readelf.txt"
grep -Eq 'Machine:[[:space:]]+ARM' "$tmpdir/readelf.txt"
rm -rf "$tmpdir"
|)
    (*install-jlink* "SEGGER J-Link command-line tools by checking their pinned version"
                     ,(format nil #r|set -eu
JLinkGDBServerCLExe -version > /tmp/jlink-version.txt
grep -F 'V~a ' /tmp/jlink-version.txt
command -v JLinkExe >/dev/null
| *jlink-version*))
    (*install-teamcity-cli* "TeamCity CLI by checking the installed version"
                            #r|set -eu
teamcity --version > /tmp/teamcity-version.txt
[ -s /tmp/teamcity-version.txt ]
grep -Eq '[0-9]+\.[0-9]+' /tmp/teamcity-version.txt
|)
    (*install-habit-hooks* "Habit Hooks by checking the CLI help"
                           #r|set -eu
habit-hooks --help > /tmp/habit-hooks-help.txt
[ -s /tmp/habit-hooks-help.txt ]
|)
    (*install-deptry* "Deptry by checking the CLI version"
                      #r|set -eu
deptry --version
|)
    (*install-jscpd* "JSCPD by checking the CLI version"
                     #r|set -eu
jscpd --version
|)
    (*install-archify* "Archify and its headless Chrome runtime"
		       #r|set -eu
archify_dir=/root/.agents/skills/archify
test -f "$archify_dir/SKILL.md"
test -f "$archify_dir/bin/archify.mjs"
node "$archify_dir/bin/archify.mjs" doctor
test -x "$ARCHIFY_CHROME"
"$ARCHIFY_CHROME" --headless --no-sandbox --disable-gpu --dump-dom about:blank > /tmp/archify-chrome.html
grep -qi '<html' /tmp/archify-chrome.html
tmpdir="$(mktemp -d /tmp/ai-env-archify.XXXXXX)"
node "$archify_dir/bin/archify.mjs" demo "$tmpdir"
test -s "$tmpdir/archify-demo.html"
rm -rf "$tmpdir"
|)
    (*enable-cuda* "CUDA nvcc compiler by compiling and verifying a test CUDA kernel"
                   #r|set -eu
if command -v nvcc >/dev/null 2>&1 ; then
  nvcc --version
  tmpdir="$(mktemp -d /tmp/ai-env-cuda.XXXXXX)"
  cat > "$tmpdir/test.cu" <<'CU_EOF'
#include <stdio.h>
__global__ void test_kernel(void) {}
int main(void) {
  test_kernel<<<1, 1>>>();
  puts("cuda-build-ok");
  return 0;
}
CU_EOF
  nvcc "$tmpdir/test.cu" -o "$tmpdir/test"
  rm -rf "$tmpdir"
fi
|)
    (*install-gcc* "GCC by compiling and running a tiny C program"
                   #r|set -eu
tmpdir="$(mktemp -d /tmp/ai-env-gcc.XXXXXX)"
cat > "$tmpdir/test.c" <<'C_EOF'
#include <stdio.h>
int main(void) {
  puts("gcc-ok");
  return 0;
}
C_EOF
gcc "$tmpdir/test.c" -o "$tmpdir/test"
"$tmpdir/test"
|)
    (*install-rust* "Rust by compiling and running a tiny program"
                    #r|set -eu
tmpdir="$(mktemp -d /tmp/ai-env-rust.XXXXXX)"
cat > "$tmpdir/test.rs" <<'R_EOF'
fn main() {
  println!("rust-ok");
}
R_EOF
rustc "$tmpdir/test.rs" -o "$tmpdir/test"
"$tmpdir/test"
|)
    ((or *install-python* *install-python-libs*) "Python by running a tiny script"
     #r|set -eu
python3 - <<'PY_EOF'
print("python-ok")
PY_EOF
|)
    (*install-sbcl* "SBCL by evaluating a simple expression"
                    #r|set -eu
sbcl --non-interactive --eval '(princ (+ 1 2))' --eval '(quit)'
|)
    (*install-emacs* "Emacs by opening a file with the configured init"
                     #r|set -eu
tmpdir="$(mktemp -d /tmp/ai-env-emacs-open.XXXXXX)"
cat > "$tmpdir/open-me" <<'T_EOF'
hello
T_EOF
cat > "$tmpdir/check.el" <<'EMACS_EOF'
(find-file "/tmp/ai-env-emacs-open.XXXXXX/open-me")
(unless (and buffer-file-name (eq major-mode 'fundamental-mode))
  (error "Emacs failed to open a plain file"))
EMACS_EOF
sed -i "s#/tmp/ai-env-emacs-open.XXXXXX#$tmpdir#g" "$tmpdir/check.el"
emacs --batch -l /root/.emacs -l "$tmpdir/check.el"
|)
    ((and *install-emacs* *install-sbcl*) "Emacs + SLIME by opening and loading a Lisp file"
     #r|set -eu
tmpdir="$(mktemp -d /tmp/ai-env-slime.XXXXXX)"
cat > "$tmpdir/example.lisp" <<'LISP_EOF'
(+ 1 2)
LISP_EOF
cat > "$tmpdir/slime-check.el" <<'SLIME_EOF'
(require 'slime)
(setq inferior-lisp-program "sbcl")
(slime-setup '(slime-repl))
(slime)
(let ((deadline (+ (float-time) 120)))
  (while (and (not (slime-connected-p)) (< (float-time) deadline))
    (sleep-for 0.2))
  (unless (slime-connected-p)
    (error "SLIME connection timed out")))
(find-file "/tmp/ai-env-slime.XXXXXX/example.lisp")
(slime-load-file "/tmp/ai-env-slime.XXXXXX/example.lisp")
(unless (= 3 (slime-eval '(cl:+ 1 2)))
  (error "SLIME evaluation returned the wrong value"))
SLIME_EOF
sed -i "s#/tmp/ai-env-slime.XXXXXX#$tmpdir#g" "$tmpdir/slime-check.el"
emacs --batch -l /root/.emacs -l "$tmpdir/slime-check.el"
|)))
```

#### Ende von `runner-stage` (3E):
Entfernung des `(volume ...)`-Blocks und Behalten des `(cmd ("/bin/bash"))`:
```lisp
    ,@(when *enable-tests*
        (test-stage))
    
    (comment "Default to launching a bash shell")
    (cmd ("/bin/bash"))))
```

---

### Teil 4: `setup02_run.sh` (Umsetzung von 3E)

Die Volume-Deklarationen wandern in das Run-Skript. Dadurch entstehen keine verwaisten anonymen Docker-Volumes auf der Host-Maschine mehr:

```bash
#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${1:-ai-env:latest}"
WORKSPACE_SRC="${WORKSPACE_SRC:-$(pwd)/src}"

# Lokale Konfigurationsverzeichnisse auf dem Host anlegen, falls nicht vorhanden
mkdir -p "$WORKSPACE_SRC" \
         "${HOME}/.config" \
         "${HOME}/.config/tc" \
         "${HOME}/.cache" \
         "${HOME}/.gemini" \
         "${HOME}/.grok" \
         "${HOME}/.codex" \
         "${HOME}/.azure" \
         "${HOME}/.cargo"

echo "Starte Container aus Image '$IMAGE_NAME'..."

exec docker run -it --rm \
  --net=host \
  -v "${WORKSPACE_SRC}:/workspace/src" \
  -v "${HOME}/.config:/root/.config" \
  -v "${HOME}/.config/tc:/root/.config/tc" \
  -v "${HOME}/.cache:/root/.cache" \
  -v "${HOME}/.gemini:/root/.gemini" \
  -v "${HOME}/.grok:/root/.grok" \
  -v "${HOME}/.codex:/root/.codex" \
  -v "${HOME}/.azure:/root/.azure" \
  -v "${HOME}/.cargo:/root/.cargo" \
  "$IMAGE_NAME" "$@"
```
