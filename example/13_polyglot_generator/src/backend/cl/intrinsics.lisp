;;;; intrinsics.lisp --- CL backend: intrinsic expansions and runtime prelude

(in-package :polyglot)

(defun cl-format-directives (fmt)
  "Translate {} / {:.Nf} / {{ / }} into CL FORMAT directives."
  (let ((out (make-string-output-stream)) (i 0) (n (length fmt)))
    (loop while (< i n)
          do (let ((ch (char fmt i)))
               (cond ((and (char= ch #\{) (< (1+ i) n) (char= #\{ (char fmt (1+ i))))
                      (write-char #\{ out) (incf i 2))
                     ((and (char= ch #\}) (< (1+ i) n) (char= #\} (char fmt (1+ i))))
                      (write-char #\} out) (incf i 2))
                     ((char= ch #\{)
                      (let* ((end (position #\} fmt :start i))
                             (spec (subseq fmt (1+ i) end)))
                        (if (string= spec "")
                            (write-string "~a" out)
                            (format out "~~,~af" (subseq spec 2 (1- (length spec)))))
                        (setf i (1+ end))))
                     ((char= ch #\~) (write-string "~~" out) (incf i))
                     (t (write-char ch out) (incf i)))))
    (get-output-stream-string out)))

(defun format-string-call-p (e)
  (and (typep e 'call-expr) (eq :intrinsic (ir-call-kind e))
       (string= "format-string" (ir-name e))))

(defun cl-print-line (e args)
  (let ((arg (first (ir-args e))))
    (if (format-string-call-p arg)
        `(format t ,(concatenate 'string (cl-format-directives (ir-value (first (ir-args arg)))) "~%")
                 ,@(mapcar #'cl-form (rest (ir-args arg))))
        `(write-line ,(first args)))))

(defun cl-key-predicate (ty)
  (if (eq :string (borrow-target ty)) ''string< ''<))

(defun cl-intrinsic-call (e args)
  (let* ((name (ir-name e))
         (a (first args)) (b (second args)) (c (third args))
         (ty (and (ir-args e) (strip-indirection (ir-ty (first (ir-args e)))))))
    (cond
      ((string= name "print-line") (cl-print-line e args))
      ((string= name "format-string")
       `(format nil ,(cl-format-directives (ir-value (first (ir-args e)))) ,@(rest args)))
      ((string= name "length") (if (eq :map (type-head ty)) `(hash-table-count ,a) `(length ,a)))
      ((string= name "string-byte-length") `(,(rt-sym "pg-utf8-length") ,a))
      ((string= name "string-char-count") `(length ,a))
      ((string= name "push") `(vector-push-extend ,a ,b))
      ((string= name "map-get") `(values (gethash ,b ,a)))
      ((string= name "map-set") `(setf (gethash ,b ,a) ,c))
      ((string= name "map-contains") `(nth-value 1 (gethash ,b ,a)))
      ((string= name "map-keys-sorted") `(,(rt-sym "pg-sorted-keys") ,a ,(cl-key-predicate (second ty))))
      ((string= name "string-concat") `(concatenate 'string ,@args))
      ((string= name "to-float") `(float ,a 1d0))
      ((string= name "int-to-string") `(princ-to-string ,a))
      ((string= name "string-find") `(or (position ,b ,a :start ,c) -1))
      ((string= name "string-slice") `(subseq ,a ,b ,c))
      ((member name '("sqrt" "abs" "min" "max" "mod" "rem") :test #'string=)
       `(,(find-symbol (string-upcase name) :cl) ,@args))
      ((member name '("truncate" "floor") :test #'string=)
       `(values (,(find-symbol (string-upcase name) :cl) ,@args)))
      (t (intrinsic-expansion (ir-target e) :cl (ir-source e))))))

(dolist (name '("print-line" "format-string" "length" "string-byte-length" "string-char-count"
                "push" "map-get" "map-set" "map-contains" "map-keys-sorted" "string-concat"
                "sqrt" "abs" "min" "max" "truncate" "floor" "mod" "rem" "to-float" "int-to-string"
                "string-find" "string-slice"))
  (define-intrinsic-expansion name :cl :function 'cl-intrinsic-call))

(defparameter +cl-prelude+
  "(defpackage :~a
  (:use :cl)
  (:export #:pg-vec #:pg-clone #:pg-utf8-length #:pg-sorted-keys))

(in-package :~:*~a)

(defun pg-vec (&rest items)
  \"Adjustable vector with fill pointer: the representation of (vec T).\"
  (make-array (length items) :adjustable t :fill-pointer t :initial-contents items))

(defgeneric pg-clone (x)
  (:documentation \"Deep copy with the value semantics of the other targets.\"))

(defmethod pg-clone (x)
  x)

(defmethod pg-clone ((x vector))
  (if (stringp x)
      x
      (let ((copy (make-array (length x) :adjustable t :fill-pointer t)))
        (dotimes (i (length x) copy)
          (setf (aref copy i) (pg-clone (aref x i)))))))

(defmethod pg-clone ((x hash-table))
  (let ((copy (make-hash-table :test (hash-table-test x))))
    (maphash (lambda (k v) (setf (gethash k copy) (pg-clone v))) x)
    copy))

(defun pg-utf8-length (s)
  \"Number of bytes of S in UTF-8.\"
  (loop for c across s
        sum (let ((code (char-code c)))
              (cond ((< code #x80) 1) ((< code #x800) 2) ((< code #x10000) 3) (t 4)))))

(defun pg-sorted-keys (map predicate)
  \"The keys of MAP sorted with PREDICATE, as a vec.\"
  (apply #'pg-vec (sort (loop for k being the hash-keys of map collect k) predicate)))
"
  "Runtime helpers of the CL backend (written only when used).")

(defun cl-prelude-text ()
  (format nil +cl-prelude+ (cl-package-name :rt)))
