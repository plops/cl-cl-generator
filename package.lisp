(defpackage :cl-cl-generator
  (:use :cl :alexandria)
  (:export
   ;; Main entry points
   :write-source
   :emit-cl
   :*cl-pprint-dispatch*

   ;; DSL keywords handled by custom pretty printing
   :toplevel
   :do0
   :comment
   :comments
   :raw))
