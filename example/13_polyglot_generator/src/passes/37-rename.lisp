;;;; 37-rename.lisp --- target names: role conventions, reserved words,
;;;; shadowing and collisions (E3/E4, modeled after Haxe renameVars.ml)
;;;;
;;;; Config keys (backend-config):
;;;;   :naming        alist role -> convention (:snake :pascal :camel :upper-snake :kebab)
;;;;                  roles: :type :function :method :field :constant :variable :module
;;;;   :reserved      list of reserved words (compared after the conversion)
;;;;   :escape        function (name role) -> escaped name, default appends _
;;;;   :shadowing     :allow (keep), :block (keep, emitter opens blocks), :rename
;;;;   :private-prefix  prefix for private module level items (Python: "_")
;;;;   :export-case   (public-convention . private-convention) for items (Go)
;;;;   :receiver-name fixed name of method receivers ("self")

(in-package :polyglot)

(defun role-convention (role)
  (or (cdr (assoc role (config-get :naming))) :snake))

(defun escape-reserved (name role)
  (if (member name (config-get :reserved) :test #'string=)
      (funcall (or (config-get :escape) (lambda (n r) (declare (ignore r)) (concatenate 'string n "_")))
               name role)
      name))

(defun target-name-for (spelling role &key visibility entry-module)
  "Target name of SPELLING in ROLE, before collision handling."
  (let* ((export (config-get :export-case))
         (convention (if (and export (member role '(:type :function :constant :method :field)))
                         (if (eq visibility :public) (car export) (cdr export))
                         (role-convention role)))
         (base (convert-case spelling convention))
         (prefix (config-get :private-prefix)))
    (escape-reserved (if (and prefix (eq visibility :private) (not entry-module)
                              (member role '(:type :function :constant)))
                         (concatenate 'string prefix base)
                         base)
                     role)))

(defun check-collisions (nodes what)
  "Signal a dsl-error when two NODES (with distinct names) share a target name."
  (let ((seen (make-hash-table :test 'equal)))
    (dolist (n nodes)
      (let ((old (gethash (ir-target-name n) seen)))
        (when (and old (string/= (ir-name old) (ir-name n)))
          (dsl-error (ir-source n) "~a ~a and ~a both map to ~a" what (ir-name old) (ir-name n)
                     (ir-target-name n)))
        (setf (gethash (ir-target-name n) seen) n)))))

(defun item-role (item)
  (etypecase item
    (method-item :method)
    ((or function-item extern-item) :function)
    ((or struct-item interface-item) :type)
    (const-item :constant)))

(defun root-method (m)
  (loop for x = m then (ir-super-target x)
        while (ir-super-target x)
        finally (return x)))

(defun method-visibility (m)
  (let ((owner (ir-owner-item (root-method m))))
    (if owner (ir-visibility owner) :private)))

(defun rename-type-members (item)
  (when (typep item 'struct-item)
    (dolist (f (ir-fields item))
      (setf (ir-target-name f) (target-name-for (ir-name f) :field :visibility (ir-visibility item))))
    (check-collisions (ir-fields item) "field"))
  (dolist (m (ir-methods item))
    (setf (ir-target-name m) (target-name-for (ir-name m) :method :visibility (method-visibility m))))
  (check-collisions (ir-methods item) "method"))

(defun rename-items (module)
  (let ((entry (ir-entry-p module)))
    (setf (ir-target-name module) (target-name-for (ir-name module) :module))
    (dolist (item (ir-items module))
      (setf (ir-target-name item)
            (target-name-for (ir-name item) (item-role item)
                             :visibility (ir-visibility item) :entry-module entry))
      (when (typep item '(or struct-item interface-item))
        (rename-type-members item)))
    (check-collisions (ir-items module) "item")))
