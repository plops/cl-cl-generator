;;;; 03-names.lisp --- source spelling of symbols and role based case conversion

(in-package :polyglot)

(defun form-name (thing)
  "Lower case source spelling of a symbol, used to recognize DSL forms by name
independent of the package. Returns NIL for non-symbols."
  (when (and thing (symbolp thing))
    (string-downcase (symbol-name thing))))

(defun form-is (thing &rest names)
  "True when THING is a symbol whose name is one of NAMES (case insensitive)."
  (let ((n (form-name thing)))
    (and n (member n names :test #'string=))))

(defun source-spelling (name)
  "Invert the effect of readtable-case :invert on the string NAME. A name
without lower case letters was written in lower case, a name without upper
case letters was written in upper case; mixed names are kept verbatim."
  (let ((upper (some #'upper-case-p name))
        (lower (some #'lower-case-p name)))
    (cond ((and upper lower) name)
          (upper (string-downcase name))
          (lower (string-upcase name))
          (t name))))

(defun spelling (thing)
  "Source spelling of the symbol or string THING."
  (etypecase thing
    (string thing)
    (symbol (source-spelling (symbol-name thing)))))

(defun verbatim-name-p (name)
  "A name with mixed case letters (e.g. Point, HTTPServer) is emitted verbatim."
  (and (some #'upper-case-p name) (some #'lower-case-p name)))

(defun check-identifier (name)
  "Signal DSL-ERROR unless NAME is a valid DSL identifier: letters, digits, -
and _, optionally wrapped in earmuffs or plus signs. cl-change-case would
silently drop other characters, so they are rejected here."
  (when (zerop (length name))
    (dsl-error name "empty identifier"))
  (let ((trimmed (string-trim "*+" name)))
    (when (zerop (length trimmed))
      (dsl-error name "identifier ~s has no letters" name))
    (loop for ch across trimmed
          unless (or (alphanumericp ch) (member ch '(#\- #\_)))
          do (dsl-error name "invalid character ~s in identifier ~s" ch name))
    name))

(defun change-case (name fn)
  "Validate NAME; verbatim names are returned unchanged, all others are
converted by FN, a cl-change-case function (it splits at - and _ and drops
earmuffs and plus signs)."
  (if (verbatim-name-p (check-identifier name))
      name
      (funcall fn name)))

(defun to-snake (name)
  "point-3d -> point_3d."
  (change-case name #'cl-change-case:snake-case))

(defun to-upper-snake (name)
  "max-size -> MAX_SIZE."
  (change-case name #'cl-change-case:constant-case))

(defun merged-camel-case (name)
  "camel-case with :merge-numbers, so that point-3d becomes point3d (the
default would be point_3d)."
  (cl-change-case:camel-case name :merge-numbers t))

(defun to-camel (name)
  "point-3d -> point3d, http-server -> httpServer."
  (change-case name #'merged-camel-case))

(defun to-pascal (name)
  "point-3d -> Point3d."
  (change-case name (lambda (n) (cl-change-case:upper-case-first (merged-camel-case n)))))

(defun to-kebab (name)
  "Identity for Lisp: the name as written in the source."
  (when (zerop (length name))
    (dsl-error name "empty identifier"))
  name)

(defun convert-case (name convention)
  "Apply CONVENTION (:snake :upper-snake :pascal :camel :kebab) to NAME."
  (ecase convention
    (:snake (to-snake name))
    (:upper-snake (to-upper-snake name))
    (:pascal (to-pascal name))
    (:camel (to-camel name))
    (:kebab (to-kebab name))))
