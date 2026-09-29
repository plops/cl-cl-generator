;;;; items.lisp --- Go backend: structs, methods, interfaces, functions

(in-package :polyglot)

(defun go-ret (ty) (let ((r (go-type ty))) (and (plusp (length r)) r)))

(defun go-params (params)
  (format nil "~{~a~^, ~}" (loop for p in params collect (format nil "~a ~a" (ir-target-name p) (go-param-type p)))))

(defun go-body (fn)
  (let ((*go-function* fn) (*go-loop-pointers* '()))
    (with-indent () (go-stmts (ir-body fn)))))

(defun go-doc (item)
  (when (ir-doc item) (emit-line "// ~a ~a" (ir-target-name item) (ir-doc item))))

(defun go-function (fn)
  (go-doc fn)
  (emit-line "func ~a(~a)~@[ ~a~] {" (ir-target-name fn) (go-params (ir-params fn)) (go-ret (ir-ret fn)))
  (go-body fn)
  (emit-line "}"))

(defun go-pointer-receivers-p (item)
  "Pointer receivers for all methods when one mutates or the type implements
an interface (then only *T is used as interface value)."
  (or (ir-implements-items item)
      (some (lambda (m) (eq :inout (ir-mode (method-receiver m)))) (ir-methods item))))

(defun go-receiver-name (m item)
  "Short receiver names instead of self/this (Go convention)."
  (let ((recv (method-receiver m)))
    (when (member (ir-target-name recv) '("self" "this" "self_") :test #'string=)
      (setf (ir-target-name recv) (string-downcase (subseq (ir-target-name item) 0 1))))
    (ir-target-name recv)))

(defun go-method (m item &key body-fn)
  (let ((recv (go-receiver-name m item))
        (*go-pointer-receiver* (and (go-pointer-receivers-p item) (method-receiver m))))
    (emit-line "func (~a ~:[~;*~]~a) ~a(~a)~@[ ~a~] {" recv (go-pointer-receivers-p item) (ir-target-name item)
               (ir-target-name m) (go-params (rest (ir-params m))) (go-ret (ir-ret m)))
    (if body-fn
        (with-indent () (funcall body-fn recv))
        (go-body m))
    (emit-line "}")))

(defun default-function-name (iface m)
  (target-name-for (format nil "~a-~a" (ir-name iface) (ir-name m)) :function
                   :visibility (ir-visibility iface)))

(defun go-default-delegations (item)
  "Methods for interface defaults the struct does not override."
  (loop for (nil . impl) in (ir-vtable item)
        when (and (typep (ir-owner-item impl) 'interface-item) (not (function-flag-p impl :abstract)))
        do (emit-blank-line)
        (let ((iface (ir-owner-item impl)))
          (go-method impl item
                     :body-fn (lambda (recv)
                                (emit-line "~:[~;return ~]~a(~a~{, ~a~})" (go-ret (ir-ret impl))
                                           (go-item-ref-name iface (default-function-name iface impl))
                                           recv (mapcar #'ir-target-name (rest (ir-params impl)))))))))

(defun go-item-ref-name (item name)
  (let ((module (ir-module item)))
    (if (or (null module) (eq module *go-module*))
        name
        (progn (note-import (list :pkg (ir-target-name module)))
               (format nil "~a.~a" (ir-target-name module) name)))))

(defun go-struct (item)
  (go-doc item)
  (with-block ((format nil "type ~a struct {" (ir-target-name item)) "}")
    (dolist (f (ir-fields item))
      (emit-line "~a ~a" (ir-target-name f) (go-type (ir-ty f)))))
  (dolist (m (ir-methods item))
    (emit-blank-line)
    (go-method m item))
  (go-default-delegations item))

(defun go-interface (item)
  (go-doc item)
  (with-block ((format nil "type ~a interface {" (ir-target-name item)) "}")
    (dolist (e (ir-extends-items item)) (emit-line (go-item-ref e)))
    (dolist (m (ir-methods item))
      (emit-line "~a(~a)~@[ ~a~]" (ir-target-name m) (go-params (rest (ir-params m))) (go-ret (ir-ret m)))))
  ;; default methods become free functions taking the interface value
  (dolist (m (ir-methods item))
    (unless (function-flag-p m :abstract)
      (emit-blank-line)
      (let ((recv (method-receiver m)))
        (when (member (ir-target-name recv) '("self" "this" "self_") :test #'string=)
          (setf (ir-target-name recv) (string-downcase (subseq (ir-target-name item) 0 1))))
        (emit-line "func ~a(~a ~a~:[~*~;, ~a~])~@[ ~a~] {" (default-function-name item m)
                   (ir-target-name recv) (ir-target-name item) (rest (ir-params m))
                   (go-params (rest (ir-params m))) (go-ret (ir-ret m)))
        (go-body m)
        (emit-line "}")))))

(defmethod emit-item ((b go-backend) item)
  (etypecase item
    (function-item (go-function item))
    (struct-item (go-struct item))
    (interface-item (go-interface item))
    (const-item (emit-line "const ~a ~a = ~a" (ir-target-name item) (go-type (ir-ty item)) (ex-str (ir-value item))))
    (extern-item nil)))
