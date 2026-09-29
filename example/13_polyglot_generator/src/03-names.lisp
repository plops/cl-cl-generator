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

(defun name-words (name)
  "Split NAME into words at - and _. Earmuffs and plus signs are dropped."
  (when (zerop (length name))
    (dsl-error name "empty identifier"))
  (let ((trimmed (string-trim "*+" name)))
    (when (zerop (length trimmed))
      (dsl-error name "identifier ~s has no letters" name))
    (loop for ch across trimmed
          unless (or (alphanumericp ch) (member ch '(#\- #\_)))
          do (dsl-error name "invalid character ~s in identifier ~s" ch name))
    (remove "" (cl-ppcre:split "[-_]" trimmed) :test #'string=)))

(defun capitalize-word (word)
  (concatenate 'string (string-upcase (subseq word 0 1))
               (string-downcase (subseq word 1))))

(defun join-words (words separator)
  (format nil (concatenate 'string "~{~a~^" separator "~}") words))

(defun to-snake (name)
  "point-3d -> point_3d. Verbatim names are returned unchanged."
  (if (verbatim-name-p name)
      name
      (join-words (mapcar #'string-downcase (name-words name)) "_")))

(defun to-upper-snake (name)
  "max-size -> MAX_SIZE."
  (if (verbatim-name-p name)
      name
      (join-words (mapcar #'string-upcase (name-words name)) "_")))

(defun to-pascal (name)
  "point-3d -> Point3d."
  (if (verbatim-name-p name)
      name
      (apply #'concatenate 'string (mapcar #'capitalize-word (name-words name)))))

(defun to-camel (name)
  "point-3d -> point3d, http-server -> httpServer."
  (if (verbatim-name-p name)
      name
      (let ((words (name-words name)))
        (apply #'concatenate 'string (string-downcase (first words))
               (mapcar #'capitalize-word (rest words))))))

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
