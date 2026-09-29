;;;; config.lisp --- Rust backend: configuration and operator table

(in-package :polyglot)

(defclass rust-backend (backend) ()
  (:documentation "Rust (edition 2021) backend: idiomatic borrowing, traits, lifetimes."))

(register-backend (make-instance 'rust-backend :key :rust))

(defmethod backend-directory ((b rust-backend)) "rust")

(defparameter +rust-reserved+
  '("as" "break" "const" "continue" "crate" "else" "enum" "extern" "false" "fn" "for" "if"
    "impl" "in" "let" "loop" "match" "mod" "move" "mut" "pub" "ref" "return" "self" "Self"
    "static" "struct" "super" "trait" "true" "type" "unsafe" "use" "where" "while" "async"
    "await" "dyn" "abstract" "become" "box" "do" "final" "macro" "override" "priv" "typeof"
    "unsized" "virtual" "yield" "try" "gen" "std" "polyglot_rt")
  "Rust keywords (raw identifiers r#x) and names the generated code uses.")

(defun rust-escape (name role)
  (declare (ignore role))
  (if (member name '("self" "Self" "crate" "super" "std" "polyglot_rt") :test #'string=)
      (concatenate 'string name "_")
      (concatenate 'string "r#" name)))

(defmethod backend-config ((b rust-backend))
  (list :naming '((:type . :pascal) (:function . :snake) (:method . :snake) (:field . :snake)
                  (:constant . :upper-snake) (:variable . :snake) (:module . :snake))
        :reserved +rust-reserved+
        :escape #'rust-escape
        :shadowing :allow
        :receiver-name "self"
        :capabilities '(:block-expressions t :ternary nil :multi-statement-lambda t
                        :implementation-inheritance nil :inout-scalars t :inout-rebind t)))

(defparameter +rust-ops+
  (make-op-table
   :entries '((:op :postfix :level 20)
              (:op :neg :token "-" :level 17) (:op :neg-literal :level 17)
              (:op :not :token "!" :level 17) (:op :bitnot :token "!" :level 17)
              (:op :ref :token "&" :level 17) (:op :deref :token "*" :level 17)
              (:op :cast :token "as" :level 16)
              (:op :mul :token "*" :level 15) (:op :div :token "/" :level 15)
              (:op :rem :token "%" :level 15)
              (:op :add :token "+" :level 14) (:op :sub :token "-" :level 14)
              (:op :shl :token "<<" :level 13) (:op :shr :token ">>" :level 13)
              (:op :bitand :token "&" :level 12) (:op :bitxor :token "^" :level 11)
              (:op :bitor :token "|" :level 10)
              (:op :eq :token "==" :level 9 :assoc :non) (:op :ne :token "!=" :level 9 :assoc :non)
              (:op :lt :token "<" :level 9 :assoc :non) (:op :le :token "<=" :level 9 :assoc :non)
              (:op :gt :token ">" :level 9 :assoc :non) (:op :ge :token ">=" :level 9 :assoc :non)
              (:op :and :token "&&" :level 8) (:op :or :token "||" :level 7)
              (:op :block :level 3) (:op :lambda :level 2))
   ;; clippy::precedence: arithmetic mixed with shifts
   :clarity '(((:shl :shr) (:add :sub :mul :div :rem))
              ((:add :sub :mul :div :rem) (:shl :shr))))
  "Rust operator precedence (cl-rust-generator/operator-precedence.md).")

(defmethod backend-op-table ((b rust-backend)) +rust-ops+)
