;;;; test-types.lisp --- tests of src/ir/11-types.lisp

(in-package :polyglot.tests)

(def-suite :polyglot.unit.types :in :polyglot.unit)
(in-suite :polyglot.unit.types)

(defun pt (string) (parse-type (read-dsl string)))

(test primitive-types
  (is (eq :i64 (pt ":int")))
  (is (eq :f64 (pt ":f64")))
  (is (eq :string (pt ":string")))
  (signals dsl-error (pt ":float")))

(test compound-types
  (is (equal '(:vec :i64) (pt "(vec :int)")))
  (is (equal '(:array :f32 4) (pt "(array :f32 4)")))
  (is (equal '(:map :string (:vec :i64)) (pt "(map :string (vec :int))")))
  (is (equal '(:optional (:named "point")) (pt "(optional point)")))
  (is (equal '(:box (:dyn "shape")) (pt "(box (dyn shape))")))
  (is (equal '(:fn (:i64 :i64) :bool) (pt "(fn (:int :int) :bool)")))
  (is (equal '(:named "Point") (pt "Point"))))

(test borrowed-types
  (is (equal '(:ref (:vec :i64) :a) (pt "(ref (vec :i64) :a)")))
  (is (equal '(:view :string :static) (pt "(view :string :static)")))
  (is (equal '(:mut-ref (:named "parser") nil) (pt "(mut-ref parser)")))
  (is (borrowed-type-p (pt "(view (vec :i64))")))
  (is (not (borrowed-type-p (pt "(vec :i64)")))))

(test raw-target-type
  (is (equal '(:raw :rust "&'static [u8]") (parse-type '(polyglot.rs::type "&'static [u8]")))))

(test copy-types
  (is (copy-type-p :i64))
  (is (copy-type-p :bool))
  (is (not (copy-type-p :string)))
  (is (not (copy-type-p '(:vec :i64))))
  (is (copy-type-p '(:view :string nil))))

(test regions
  (is (equal '(:a :anon) (type-regions (pt "(map (ref :i64 :a) (view :string))"))))
  (is (equal '(:a) (type-regions (pt "(vec (ref (ref :i64 :a) :a))"))))
  (is (null (type-regions :i64))))

(test type-errors
  (signals dsl-error (pt "(vec)"))
  (signals dsl-error (pt "(array :i64 0)"))
  (signals dsl-error (pt "(view :i64)"))
  (signals dsl-error (pt "(ref :i64 a)"))
  (signals dsl-error (pt "(frobnicate :i64)"))
  (signals dsl-error (pt "42")))

(test type-string-readable
  (is (string= "(vec :i64)" (type-string '(:vec :i64))))
  (is (string= "point" (type-string '(:named "point")))))
