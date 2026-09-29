;;;; 60-protocol.lisp --- backend protocol: class, registry, generic functions

(in-package :polyglot)

(defclass backend ()
  ((key :initarg :key :reader backend-key :documentation "Keyword, e.g. :cpp."))
  (:documentation "Base class of all backends; one subclass per target language."))

(defvar *backends* (make-hash-table) "Backend key -> backend instance.")
(defvar *backend* nil "The backend instance while artifacts are generated.")
(defvar *mode* :minimal "Parenthesization mode: :minimal (output) or :full (oracle).")

(defun register-backend (instance)
  (setf (gethash (backend-key instance) *backends*) instance))

(defun find-backend (key)
  (or (gethash key *backends*)
      (error 'unsupported-construct :form key :backend key
             :message (format nil "no backend ~(~s~) (known: ~{~(~a~)~^, ~})"
                              key (sort (alexandria:hash-table-keys *backends*)
                                        #'string<)))))

(defgeneric backend-config (backend)
  (:documentation "Plist: :backend :naming :reserved :escape :shadowing :private-prefix
:export-case :receiver-name :capabilities :unspecified-arg-order :unsupported-nodes."))

(defgeneric backend-directory (backend)
  (:documentation "Name of the output sub directory of BACKEND.")
  (:method ((b backend)) (string-downcase (symbol-name (backend-key b)))))

(defgeneric emit-expr (backend expr)
  (:documentation "Text of EXPR: (values string effective-operator)."))

(defgeneric emit-stmt (backend stmt)
  (:documentation "Emit STMT as lines into *WRITER*."))

(defgeneric emit-item (backend item)
  (:documentation "Emit the module level ITEM."))

(defgeneric module-artifacts (backend module)
  (:documentation "List of ARTIFACTs of MODULE (after the passes ran)."))

(defgeneric project-artifacts (backend project)
  (:documentation "All artifacts of PROJECT: modules plus build files and preludes.")
  (:method ((b backend) project)
    (loop for m in (ir-modules project) append (module-artifacts b m))))

(defun generate-artifacts (backend project &key (mode :minimal))
  "Run the passes configured for BACKEND on (a copy of) PROJECT and return its
artifacts."
  (let* ((*backend* backend)
         (*mode* mode)
         (*current-backend* (backend-key backend))
         (config (list* :backend (backend-key backend) (backend-config backend)))
         (lowered (run-passes project config))
         (*config* config))
    (project-artifacts backend lowered)))
