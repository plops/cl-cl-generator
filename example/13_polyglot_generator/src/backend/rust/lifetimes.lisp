;;;; lifetimes.lisp --- Rust backend: lifetimes from borrow relations (K1b)
;;;;
;;;; Named regions (:a) become 'a. Without borrows-from the Rust elision rules
;;;; apply (one reference parameter, or &self) and no lifetime is written
;;;; (clippy::needless_lifetimes). With borrows-from the listed parameters
;;;; and the unnamed regions of the result share 'a. Methods of structs with
;;;; borrowed fields return the struct lifetime.

(in-package :polyglot)

(defun lifetime-name (region)
  (format nil "'~(~a~)" (if (eq region :anon) "a" (symbol-name region))))

(defun named-regions (types)
  (remove-duplicates (remove-if (lambda (r) (member r '(:anon :static)))
                                (loop for ty in types append (type-regions ty)))
                     :from-end t))

(defun rs-fn-lifetimes (fn &key struct-regions)
  "Values: generic lifetimes to declare on FN, regions alist for the result,
alist var-def -> regions alist for every parameter, and *rs-param-regions*."
  (let* ((params (remove-if #'ir-receiver-p (ir-params fn)))
         (named (named-regions (cons (ir-ret fn) (mapcar #'ir-ty params))))
         (named-alist (mapcar (lambda (r) (cons r (lifetime-name r))) named))
         (from (ir-borrows-from fn))
         (anon-borrow (and from (member :anon (type-regions (ir-ret fn)))))
         (struct-lt (and struct-regions (borrowed-type-p* (ir-ret fn))
                         (lifetime-name (first struct-regions)))))
    (values (remove-duplicates (append (mapcar #'cdr named-alist) (when anon-borrow (list "'a")))
                               :test #'string= :from-end t)
            (cond (anon-borrow (acons :anon "'a" named-alist))
                  (struct-lt (acons :anon struct-lt named-alist))
                  (t named-alist))
            (loop for p in params
                  collect (cons p (if (and anon-borrow (member (ir-name p) from :test #'string=))
                                      (acons :anon "'a" named-alist)
                                      named-alist)))
            (loop for p in params
                  when (and anon-borrow (member (ir-name p) from :test #'string=)
                            (not (borrowed-type-p (ir-ty p))))
                  collect (cons p :anon)))))

(defun borrowed-type-p* (ty)
  "TY contains a borrowed type (also inside optional, vec, ...)."
  (and (type-regions ty) t))

(defun rs-param-decl (p regions pushes)
  (let ((*rs-regions* regions))
    (format nil "~:[~;_~]~a: ~a" (not (ir-used p)) (ir-target-name p)
            (rs-param-type p :pushes (member p pushes)))))

(defun pushed-params (fn)
  "Parameters that are the container of a push (they stay &mut Vec<T>)."
  (let ((out '()))
    (dolist (s (ir-body fn) out)
      (walk-nodes (lambda (n)
                    (when (and (intrinsic-name-is n "push") (typep (second (ir-args n)) 'var-expr))
                      (pushnew (ir-binding (second (ir-args n))) out)))
                  s))))

(defun rs-receiver-decl (recv)
  (ecase (ir-mode recv) (:in "&self") (:inout "&mut self") (:sink "self")))

(defun rs-signature (fn &key struct-regions (pub nil))
  "fn name<'a>(params) -> ret"
  (multiple-value-bind (generics ret-regions param-regions implicit)
      (rs-fn-lifetimes fn :struct-regions struct-regions)
    (let* ((*rs-param-regions* implicit)
           (pushes (pushed-params fn))
           (recv (find-if #'ir-receiver-p (ir-params fn)))
           (params (append (when recv (list (rs-receiver-decl recv)))
                           (loop for (p . regions) in param-regions
                                 collect (rs-param-decl p regions pushes))))
           (ret (let ((*rs-regions* ret-regions)) (rs-type (ir-ret fn)))))
      (format nil "~:[~;pub ~]fn ~a~@[<~{~a~^, ~}>~](~{~a~^, ~})~:[ -> ~a~;~*~]"
              pub (ir-target-name fn) (rs-outlives-bounds generics (ir-outlives fn)) params
              (eq :void (ir-ret fn)) ret))))

(defun rs-outlives-bounds (generics outlives)
  "'a -> 'a: 'b for every (outlives :a :b)."
  (mapcar (lambda (lt)
            (let ((bounds (loop for (a b) in outlives
                                when (string= lt (lifetime-name a)) collect (lifetime-name b))))
              (if bounds (format nil "~a: ~{~a~^ + ~}" lt bounds) lt)))
          generics))

(defun mark-used-params (fn)
  (dolist (p (ir-params fn))
    (setf (ir-used p) (param-used-p fn p))))
