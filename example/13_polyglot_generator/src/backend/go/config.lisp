;;;; config.lisp --- Go backend (Tier B, proof of R3): configuration

(in-package :polyglot)

(defclass go-backend (backend) ()
  (:documentation "Go 1.23 backend: one package per module, exports by case."))

(register-backend (make-instance 'go-backend :key :go))

(defmethod backend-directory ((b go-backend)) "go")

(defparameter +go-reserved+
  '("break" "case" "chan" "const" "continue" "default" "defer" "else" "fallthrough" "for"
    "func" "go" "goto" "if" "import" "interface" "map" "package" "range" "return" "select"
    "struct" "switch" "type" "var"
    ;; predeclared identifiers and packages the generated code uses
    "len" "append" "make" "new" "nil" "true" "false" "int" "int64" "float64" "string" "bool"
    "byte" "rune" "error" "copy" "delete" "panic" "min" "max" "cap" "close" "print" "println"
    "fmt" "math" "strconv" "utf8" "maps" "slices" "polyglotrt")
  "Go keywords and predeclared names; they get a trailing underscore.")

(defmethod backend-config ((b go-backend))
  (list :naming '((:type . :pascal) (:function . :camel) (:method . :camel) (:field . :camel)
                  (:constant . :camel) (:variable . :camel) (:module . :snake))
        :export-case '(:pascal . :camel)
        :reserved +go-reserved+
        :shadowing :rename
        :capabilities '(:block-expressions nil :ternary nil :multi-statement-lambda t
                        :implementation-inheritance nil :inout-scalars t :inout-rebind t)))

(defparameter +go-ops+
  (make-op-table
   :entries '((:op :postfix :level 20)
              (:op :neg :token "-" :level 17) (:op :neg-literal :level 17)
              (:op :not :token "!" :level 17) (:op :bitnot :token "^" :level 17)
              (:op :deref :token "*" :level 17) (:op :addr :token "&" :level 17)
              (:op :mul :token "*" :level 15) (:op :div :token "/" :level 15)
              (:op :rem :token "%" :level 15) (:op :shl :token "<<" :level 15)
              (:op :shr :token ">>" :level 15) (:op :bitand :token "&" :level 15)
              (:op :add :token "+" :level 14) (:op :sub :token "-" :level 14)
              (:op :bitor :token "|" :level 14) (:op :bitxor :token "^" :level 14)
              (:op :eq :token "==" :level 13 :assoc :non) (:op :ne :token "!=" :level 13 :assoc :non)
              (:op :lt :token "<" :level 13 :assoc :non) (:op :le :token "<=" :level 13 :assoc :non)
              (:op :gt :token ">" :level 13 :assoc :non) (:op :ge :token ">=" :level 13 :assoc :non)
              (:op :and :token "&&" :level 12) (:op :or :token "||" :level 11))
   :clarity '())
  "Go operator precedence: five binary levels.")

(defmethod backend-op-table ((b go-backend)) +go-ops+)
