(eval-when (:compile-toplevel :execute :load-toplevel)
  ;; First, load the cl-cl-generator system relative to this file.
  ;; We find the directory where this file resides and navigate up two levels to find the root system directory.
  (let ((current-dir (make-pathname :directory (pathname-directory *load-pathname*))))
    (push (merge-pathnames "../../" current-dir) asdf:*central-registry*))
  (ql:quickload :cl-cl-generator))

(defpackage :cl-cl-generator/example-meta
  (:use :cl :cl-cl-generator))

(in-package :cl-cl-generator/example-meta)

;; =========================================================================
;; HELPER FUNCTIONS (S-Expression Builders)
;; =========================================================================

;; 1. Helper to define a Vector struct dynamically.
;; Given a name (e.g. VEC2D) and a list of field names (e.g. (X Y)),
;; this returns the S-expression for (defstruct NAME FIELD1 FIELD2 ...).
(defun build-vector-struct (name fields)
  `(defstruct ,name
     ,@fields))

;; 2. Helper to define addition/subtraction functions for vectors.
;; This returns the S-expression representing a function definition:
;; (defun <VEC-OP-NAME> (v1 v2) (make-<VEC-NAME> :x (op (vec-x v1) (vec-x v2)) ...))
(defun build-vector-op (struct-name fields op-name math-op)
  (let* ((fn-name (intern (format nil "~a-~a" struct-name op-name)))
         (constructor-name (intern (format nil "MAKE-~a" struct-name)))
         ;; Map over the field list (e.g., (X Y Z)) to construct constructor arguments.
         ;; E.g., for X, this builds: :X (+ (VEC-X v1) (VEC-X v2))
         (constructor-args
           (loop for field in fields
                 append (let ((accessor (intern (format nil "~a-~a" struct-name field)))
                              (kw-arg (intern (symbol-name field) "KEYWORD")))
                          (list kw-arg `(,math-op (,accessor v1) (,accessor v2)))))))
    `(defun ,fn-name (v1 v2)
       (,constructor-name ,@constructor-args))))

;; =========================================================================
;; TEMPLATE CODE GENERATION
;; =========================================================================

(let* (;; Define the output directory and target filename.
       ;; We write it in the same directory as this generator script.
       (output-dir (asdf:system-relative-pathname :cl-cl-generator "example/01_meta/"))
       (output-filename "run_meta")

       ;; We define the vector configurations as data.
       ;; We will generate full structures and math operators for 2D vectors and 3D vectors!
       (vec-configs '((vec2d (x y))
                      (vec3d (x y z))))

       ;; Build the main S-expression template.
       ;; The backquote (`) starts the template. Inside the template, everything is literal,
       ;; EXCEPT forms prefixed with comma (,) or comma-splice (,@), which evaluate at generation-time.
       (code
         `(toplevel
            ;; Let's write some file header comments in the output code.
            (comment "This file is AUTO-GENERATED. Do not modify directly.")
            (comment "It contains struct definitions and operations for VEC2D and VEC3D.")
            
            (in-package :cl-user)

            ;; -------------------------------------------------------------
            ;; 1. GENERATE STRUCTS
            ;; -------------------------------------------------------------
            (comment "Vector Structure Definitions")
            ;; Here we loop over the configs and call our builder function 'build-vector-struct'.
            ;; The leading comma ',' forces Lisp to execute the builder function and splice
            ;; the resulting S-expressions into the list structure.
            ,@(loop for config in vec-configs
                    collect (build-vector-struct (first config) (second config)))

            ;; -------------------------------------------------------------
            ;; 2. GENERATE MATH OPERATIONS
            ;; -------------------------------------------------------------
            (comment "Vector Addition and Subtraction Operations")
            ;; We use nested loops to generate addition (+ / add) and subtraction (- / sub)
            ;; functions for all vector structures defined in 'vec-configs'.
            ;; This allows us to generate 4 distinct functions (vec2d-add, vec2d-sub, vec3d-add, vec3d-sub)
            ;; in just a few lines of generator code, completely eliminating copy-paste.
            ,@(loop for config in vec-configs
                    for name = (first config)
                    for fields = (second config)
                    append (loop for (op-name math-op) in '((add +) (sub -))
                                 collect (build-vector-op name fields op-name math-op))))))

  ;; Write the generated S-expressions as formatted Common Lisp code.
  ;; The write-source function will pretty-print the code into 'run_meta.lisp'
  ;; and ensure all indentation (like in defun and defstruct) is beautifully aligned.
  (let ((result-path (write-source output-filename code output-dir)))
    (format t "Successfully generated Vector Math Library at ~a~%" result-path)))
