;;;; 30-pipeline.lisp --- pass registry and pipeline

(in-package :polyglot)

(defstruct pass
  name          ; keyword
  order         ; number, passes run in ascending order
  fn            ; (lambda (project config)) -> project
  enabled-p     ; (lambda (config)) -> boolean
  documentation)

(defvar *passes* (make-hash-table)
  "Pass name -> PASS.")

(defvar *config* nil
  "Plist of the backend configuration while passes run (see backend-config).")

(defun config-get (key &optional default)
  (getf *config* key default))

(defun capability-p (feature)
  "Value of FEATURE in the :capabilities plist of the current config."
  (getf (config-get :capabilities) feature))

(defmacro define-pass (name (&key order (when t)) (project) &body body)
  "Define pass NAME. ORDER fixes its position; WHEN is a form evaluated with
*CONFIG* bound that decides whether the pass runs for the current backend.
The body receives PROJECT and must return the (possibly new) project."
  (let ((doc (when (stringp (car body)) (car body))))
    `(setf (gethash ,name *passes*)
           (make-pass :name ,name :order ,order :documentation ,doc
                      :fn (lambda (,project) ,@body)
                      :enabled-p (lambda () ,when)))))

(defun pass-sequence ()
  "All registered passes sorted by their order."
  (sort (alexandria:hash-table-values *passes*) #'< :key #'pass-order))

(defun enabled-passes (config)
  (let ((*config* config))
    (remove-if-not (lambda (p) (funcall (pass-enabled-p p))) (pass-sequence))))

(defun run-passes (project config &key (backend (getf config :backend)) until)
  "Run all passes enabled by CONFIG on a deep copy of PROJECT and return the
result. The input PROJECT is never modified. UNTIL stops after that pass."
  (let ((*config* config)
        (*current-backend* backend)
        (current (copy-node-tree project)))
    (dolist (p (enabled-passes config) current)
      (setf current (funcall (pass-fn p) current))
      (when (eq until (pass-name p))
        (return current)))))
