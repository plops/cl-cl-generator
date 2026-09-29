;;;; test-names.lisp --- tests of src/03-names.lisp

(in-package :polyglot.tests)

(def-suite :polyglot.unit.names :in :polyglot.unit)
(in-suite :polyglot.unit.names)

(test source-spelling-inverts
  (is (string= "point-3d" (source-spelling "POINT-3D")))
  (is (string= "POINT" (source-spelling "point")))
  (is (string= "Point" (source-spelling "Point")))
  (is (string= "HTTPServer" (spelling (read-dsl "|HTTPServer|"))))
  (is (string= "point-3d" (spelling (read-dsl "point-3d")))))

(test case-conversions
  (is (string= "point_3d" (to-snake "point-3d")))
  (is (string= "Point3d" (to-pascal "point-3d")))
  (is (string= "point3d" (to-camel "point-3d")))
  (is (string= "POINT_3D" (to-upper-snake "point-3d")))
  (is (string= "httpServer" (to-camel "http-server")))
  (is (string= "MAX_SIZE" (to-upper-snake "+max-size+")))
  (is (string= "foo_bar" (to-snake "foo_bar"))))

(test verbatim-names-stay
  (is (string= "Point" (to-snake "Point")))
  (is (string= "HTTPServer" (to-pascal "HTTPServer")))
  (is (string= "HTTPServer" (convert-case "HTTPServer" :upper-snake))))

(test invalid-names-signal
  (signals dsl-error (to-snake ""))
  (signals dsl-error (to-snake "a?b"))
  (signals dsl-error (to-kebab "")))

(test form-recognition-by-name
  (is (form-is 'polyglot.cpp::defun "defun"))
  (is (form-is (read-dsl "defun") "defun"))
  (is (not (form-is "defun" "defun")))
  (is (not (form-is 'foo "defun"))))
