;;;; config.lisp --- Python 3 backend: configuration and operator table

(in-package :polyglot)

(defclass python-backend (backend) ()
  (:documentation "Python 3 backend (dataclasses, ABC, f-strings, ruff)."))

(register-backend (make-instance 'python-backend :key :python))

(defmethod backend-directory ((b python-backend)) "python")

(defparameter +python-reserved+
  '("False" "None" "True" "and" "as" "assert" "async" "await" "break" "class" "continue"
    "def" "del" "elif" "else" "except" "finally" "for" "from" "global" "if" "import" "in"
    "is" "lambda" "nonlocal" "not" "or" "pass" "raise" "return" "try" "while" "with" "yield"
    "match" "case" "type" "self"
    ;; builtins and modules the generated code uses, plus ruff E741 names
    "print" "len" "min" "max" "abs" "int" "str" "float" "list" "dict" "sorted" "range"
    "super" "object" "math" "copy" "field" "dataclass" "l" "O" "I")
  "Words that get a trailing underscore.")

(defmethod backend-config ((b python-backend))
  (list :naming '((:type . :pascal) (:function . :snake) (:method . :snake) (:field . :snake)
                  (:constant . :upper-snake) (:variable . :snake) (:module . :snake))
        :reserved +python-reserved+
        :shadowing :rename
        :private-prefix "_"
        :receiver-name "self"
        :capabilities '(:block-expressions nil :ternary t :multi-statement-lambda nil
                        :implementation-inheritance t :inout-scalars nil :inout-rebind nil)))

(defparameter +python-ops+
  (make-op-table
   :entries '((:op :postfix :level 20)
              (:op :neg :token "-" :level 16) (:op :neg-literal :level 16)
              (:op :bitnot :token "~" :level 16)
              (:op :mul :token "*" :level 15) (:op :div :token "/" :level 15)
              (:op :floordiv :token "//" :level 15) (:op :mod :token "%" :level 15)
              (:op :add :token "+" :level 14) (:op :sub :token "-" :level 14)
              (:op :shl :token "<<" :level 13) (:op :shr :token ">>" :level 13)
              (:op :bitand :token "&" :level 12) (:op :bitxor :token "^" :level 11)
              (:op :bitor :token "|" :level 10)
              (:op :eq :token "==" :level 9 :assoc :non) (:op :ne :token "!=" :level 9 :assoc :non)
              (:op :lt :token "<" :level 9 :assoc :non) (:op :le :token "<=" :level 9 :assoc :non)
              (:op :gt :token ">" :level 9 :assoc :non) (:op :ge :token ">=" :level 9 :assoc :non)
              (:op :in :token "in" :level 9 :assoc :non)
              (:op :not :token "not " :level 8)
              (:op :and :token "and" :level 7) (:op :or :token "or" :level 6)
              (:op :if :level 5 :assoc :non) (:op :lambda :level 4 :assoc :non))
   :clarity '(((:eq :ne :lt :le :gt :ge :in) (:eq :ne :lt :le :gt :ge :in))))
  "Python operator precedence (higher binds tighter).")

(defmethod backend-op-table ((b python-backend)) +python-ops+)
