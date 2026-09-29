;;;; config.lisp --- C++20 backend: configuration and operator table

(in-package :polyglot)

(defclass cpp-backend (backend) ()
  (:documentation "C++20 backend: header/implementation split per module."))

(register-backend (make-instance 'cpp-backend :key :cpp))

(defmethod backend-directory ((b cpp-backend)) "cpp")

(defparameter +cpp-reserved+
  '("alignas" "alignof" "and" "and_eq" "asm" "auto" "bitand" "bitor" "bool" "break" "case"
    "catch" "char" "char8_t" "char16_t" "char32_t" "class" "compl" "concept" "const" "consteval"
    "constexpr" "constinit" "const_cast" "continue" "co_await" "co_return" "co_yield" "decltype"
    "default" "delete" "do" "double" "dynamic_cast" "else" "enum" "explicit" "export" "extern"
    "false" "float" "for" "friend" "goto" "if" "inline" "int" "long" "mutable" "namespace" "new"
    "noexcept" "not" "not_eq" "nullptr" "operator" "or" "or_eq" "private" "protected" "public"
    "register" "reinterpret_cast" "requires" "return" "short" "signed" "sizeof" "static"
    "static_assert" "static_cast" "struct" "switch" "template" "this" "thread_local" "throw"
    "true" "try" "typedef" "typeid" "typename" "union" "unsigned" "using" "virtual" "void"
    "volatile" "wchar_t" "while" "xor" "xor_eq" "std" "polyglot_rt")
  "C++ keywords and the namespaces the generated code refers to.")

(defmethod backend-config ((b cpp-backend))
  (list :naming '((:type . :pascal) (:function . :snake) (:method . :snake) (:field . :snake)
                  (:constant . :upper-snake) (:variable . :snake) (:module . :snake))
        :reserved +cpp-reserved+
        :shadowing :rename
        :unspecified-arg-order t
        :capabilities '(:block-expressions nil :ternary t :multi-statement-lambda t
                        :implementation-inheritance t :inout-scalars t :inout-rebind t)))

(defparameter +cpp-ops+
  (make-op-table
   :entries '((:op :postfix :level 20)
              (:op :neg :token "-" :level 17) (:op :neg-literal :level 17)
              (:op :not :token "!" :level 17) (:op :bitnot :token "~" :level 17)
              (:op :mul :token "*" :level 15) (:op :div :token "/" :level 15)
              (:op :rem :token "%" :level 15)
              (:op :add :token "+" :level 14) (:op :sub :token "-" :level 14)
              (:op :shl :token "<<" :level 13) (:op :shr :token ">>" :level 13)
              (:op :lt :token "<" :level 11 :assoc :non) (:op :le :token "<=" :level 11 :assoc :non)
              (:op :gt :token ">" :level 11 :assoc :non) (:op :ge :token ">=" :level 11 :assoc :non)
              (:op :eq :token "==" :level 10 :assoc :non) (:op :ne :token "!=" :level 10 :assoc :non)
              (:op :bitand :token "&" :level 9) (:op :bitxor :token "^" :level 8)
              (:op :bitor :token "|" :level 7)
              (:op :and :token "&&" :level 6) (:op :or :token "||" :level 5)
              (:op :cond :level 4 :assoc :right) (:op :lambda :level 3))
   ;; -Wparentheses
   :clarity '(((:or) (:and))
              ((:shl :shr) (:add :sub :mul :div :rem))
              ((:bitand :bitor :bitxor) (:add :sub :mul :div :rem :shl :shr :eq :ne :lt :le :gt :ge
                                         :bitand :bitor :bitxor))))
  "C++ operator precedence (higher binds tighter).")

(defmethod backend-op-table ((b cpp-backend)) +cpp-ops+)
