;;;; types.lisp --- C++ backend: type spelling, parameter modes, headers

(in-package :polyglot)

(defvar *cpp-module* nil "Module being emitted.")

(defun cpp-std-include (header) (note-import (list :std header)))

(defvar *cpp-by-value*)

(defun cpp-item-ref (item)
  "Name of ITEM as seen from *CPP-MODULE* (namespace qualified when foreign).
Foreign types used only in signatures (*CPP-BY-VALUE* NIL) are forward
declared instead of included (K2, Haxe gencpp)."
  (let ((module (ir-module item)))
    (if (or (null module) (eq module *cpp-module*))
        (ir-target-name item)
        (progn (if (or *cpp-by-value* (not (typep item '(or struct-item interface-item))))
                   (note-import (list :module (ir-target-name module)))
                   (note-import (list :forward (ir-target-name module) (ir-target-name item))))
               (format nil "~a::~a" (ir-target-name module) (ir-target-name item))))))

(defun cpp-int-type (ty)
  (cpp-std-include "cstdint")
  (format nil "std::~(~a~)int~d_t" (if (char= #\u (char (string-downcase (symbol-name ty)) 0)) "u" "")
          (parse-integer (symbol-name ty) :start 1)))

(defun cpp-type (ty &key field)
  "C++ spelling of TY. FIELD true: borrowed types become pointers (C.12)."
  (cond ((int-type-p ty) (cpp-int-type ty))
        ((eq ty :f64) "double")
        ((eq ty :f32) "float")
        ((eq ty :bool) "bool")
        ((eq ty :char) "char")
        ((eq ty :void) "void")
        ((eq ty :string) (cpp-std-include "string") "std::string")
        ((not (consp ty)) "auto")
        (t (cpp-compound-type ty field))))

(defun cpp-compound-type (ty field)
  (ecase (car ty)
    (:vec (cpp-std-include "vector") (format nil "std::vector<~a>" (cpp-type (second ty))))
    (:array (cpp-std-include "array") (format nil "std::array<~a, ~d>" (cpp-type (second ty)) (third ty)))
    (:map (cpp-std-include "map") (format nil "std::map<~a, ~a>" (cpp-type (second ty)) (cpp-type (third ty))))
    (:optional (cpp-std-include "optional") (format nil "std::optional<~a>" (cpp-type (second ty))))
    (:box (cpp-std-include "memory") (format nil "std::unique_ptr<~a>" (cpp-type (second ty))))
    ((:named :dyn) (cpp-item-ref (third ty)))
    (:fn (cpp-std-include "functional")
         (format nil "std::function<~a(~{~a~^, ~})>" (cpp-type (third ty)) (mapcar #'cpp-type (second ty))))
    (:ref (if field
              (format nil "const ~a*" (cpp-type (second ty)))
              (format nil "const ~a&" (cpp-type (second ty)))))
    (:mut-ref (format nil "~a~:[&~;*~]" (cpp-type (second ty)) field))
    (:view (if (eq :string (second ty))
               (progn (cpp-std-include "string_view") "std::string_view")
               (progn (cpp-std-include "span")
                      (format nil "std::span<const ~a>" (cpp-type (second (second ty)))))))
    (:raw (if (eq (second ty) :cpp) (third ty) (unsupported ty "raw type for another backend")))))

(defun cpp-param-type (var)
  "Parameter type according to the mode (K1): :in -> const T& (copy types and
views by value), :inout -> T&, :sink -> T."
  (let ((ty (ir-ty var)))
    (ecase (ir-mode var)
      (:in (if (or (copy-type-p ty) (borrowed-type-p ty) (eq :fn (type-head ty)))
               (cpp-type ty)
               (format nil "const ~a&" (cpp-type ty))))
      (:inout (format nil "~a&" (cpp-type ty)))
      (:sink (cpp-type ty)))))

(defun cpp-pointer-type-p (ty)
  "Values that are accessed with -> (box, and borrowed fields)."
  (eq :box (type-head ty)))
