;;;; tests_runner.lisp — Unit + Integration tests for protobuf-grpc-example

(eval-when (:compile-toplevel :execute :load-toplevel)
  (let ((current-dir (make-pathname :directory (pathname-directory *load-pathname*))))
    (push (merge-pathnames "source/" current-dir) asdf:*central-registry*))
  (ql:quickload '(:protobuf-grpc-example :usocket :flexi-streams) :silent t))

(defpackage :protobuf-grpc-example/tests
  (:use :cl :protobuf-grpc-example))

(in-package :protobuf-grpc-example/tests)

;;; ---- Helpers ----

(defun roundtrip-varint (val)
  (let ((bytes (flexi-streams:with-output-to-sequence (s)
                 (protobuf-grpc-example::write-varint val s))))
    (with-open-stream (s (flexi-streams:make-in-memory-input-stream bytes))
      (protobuf-grpc-example::read-varint s))))

;;; ---- [1/4] Varint encoding/decoding ----

(defun test-varints ()
  (format t "[1/4] Varint encoding/decoding...~%")
  (dolist (val '(0 1 127 128 16383 16384 2147483647 -1 -128 -2147483648))
    (let ((rt (roundtrip-varint val)))
      (unless (= val rt)
        (error "Varint mismatch: expected ~a, got ~a" val rt))))
  (format t "      PASSED~%"))

;;; ---- [2/4] Field skipping ----

(defun test-field-skipping ()
  (format t "[2/4] Field skipping for unknown tags...~%")
  (let* ((bytes
           (flexi-streams:with-output-to-sequence (s)
             ;; Known field 1 (wire-type 2): string "12345"
             (protobuf-grpc-example::write-varint (logior (ash 1 3) 2) s)
             (let ((b (flexi-streams:string-to-octets "12345" :external-format :utf-8)))
               (protobuf-grpc-example::write-varint (length b) s)
               (write-sequence b s))
             ;; Unknown field 10 (wire-type 0): varint 999
             (protobuf-grpc-example::write-varint (logior (ash 10 3) 0) s)
             (protobuf-grpc-example::write-varint 999 s)
             ;; Known field 2 (wire-type 0): varint 42
             (protobuf-grpc-example::write-varint (logior (ash 2 3) 0) s)
             (protobuf-grpc-example::write-varint 42 s)
             ;; Unknown field 11 (wire-type 2): string "skip-me"
             (protobuf-grpc-example::write-varint (logior (ash 11 3) 2) s)
             (let ((b (flexi-streams:string-to-octets "skip-me" :external-format :utf-8)))
               (protobuf-grpc-example::write-varint (length b) s)
               (write-sequence b s))
             ;; Unknown field 12 (wire-type 5): 32-bit fixed
             (protobuf-grpc-example::write-varint (logior (ash 12 3) 5) s)
             (write-byte #x11 s) (write-byte #x22 s) (write-byte #x33 s) (write-byte #x44 s)
             ;; Unknown field 13 (wire-type 1): 64-bit fixed
             (protobuf-grpc-example::write-varint (logior (ash 13 3) 1) s)
             (dotimes (i 8) (write-byte #xAA s))))
         (msg nil))
    (with-open-stream (s (flexi-streams:make-in-memory-input-stream bytes))
      (setf msg (deserialize-phone-number s)))
    (unless (string= (phone-number-number msg) "12345")
      (error "Expected number=12345, got ~a" (phone-number-number msg)))
    (unless (= (phone-number-type msg) 42)
      (error "Expected type=42, got ~a" (phone-number-type msg)))
    (format t "      PASSED~%")))

;;; ---- [3/4] Serialization round-trip ----

(defun test-serialization-round-trip ()
  (format t "[3/4] Serialization round-trip (Person w/ nested PhoneNumbers)...~%")
  (let* ((p1 (make-person :name "Alice"
                          :id 101
                          :email "alice@example.com"
                          :phones (list (make-phone-number :number "111-222" :type 1)
                                        (make-phone-number :number "333-444" :type 2))))
         (bytes (flexi-streams:with-output-to-sequence (s) (serialize-person p1 s)))
         (p2 nil))
    (with-open-stream (s (flexi-streams:make-in-memory-input-stream bytes))
      (setf p2 (deserialize-person s)))
    (unless (string= (person-name p1)  (person-name p2))   (error "Name mismatch"))
    (unless (= (person-id p1)          (person-id p2))     (error "ID mismatch"))
    (unless (string= (person-email p1) (person-email p2))  (error "Email mismatch"))
    (unless (= (length (person-phones p1)) (length (person-phones p2)))
      (error "Phone list length mismatch"))
    (loop for ph1 in (person-phones p1)
          for ph2 in (person-phones p2)
          do (unless (string= (phone-number-number ph1) (phone-number-number ph2))
               (error "Phone number mismatch"))
             (unless (= (phone-number-type ph1) (phone-number-type ph2))
               (error "Phone type mismatch")))
    (format t "      PASSED~%")))

;;; ---- [4/4] Integration: TCP loopback ----

(defclass mock-service (address-book-service)
  ((db :accessor service-db :initform (make-address-book))))

(defmethod add-person ((impl mock-service) (req person))
  (when (string= (person-name req) "trigger-error")
    (error "Simulated server-side error!"))
  (push req (address-book-people (service-db impl)))
  (service-db impl))

(defmethod get-people ((impl mock-service) (req get-people-request))
  (let ((query (get-people-request-query req))
        (res   (make-address-book)))
    (dolist (p (address-book-people (service-db impl)))
      (when (or (string= query "") (search query (person-name p)))
        (push p (address-book-people res))))
    res))

(defun test-integration ()
  (format t "[4/4] Integration test (TCP loopback, RPC calls, remote exception)...~%")
  (let* ((impl          (make-instance 'mock-service))
         (port          50051)
         (server-socket (start-address-book-service-server impl "127.0.0.1" port)))
    (sleep 0.5)
    (unwind-protect
         (let* ((sock   (usocket:socket-connect "127.0.0.1" port :element-type '(unsigned-byte 8)))
                (stream (usocket:socket-stream sock)))
           (unwind-protect
                (progn
                  ;; AddPerson
                  (let ((book (call-add-person stream
                                (make-person :name "Alice" :id 1 :email "alice@example.com"))))
                    (unless (= 1 (length (address-book-people book)))
                      (error "AddPerson: expected 1 person")))
                  ;; GetPeople
                  (let ((book (call-get-people stream (make-get-people-request :query ""))))
                    (unless (= 1 (length (address-book-people book)))
                      (error "GetPeople: expected 1 person")))
                  ;; Remote error propagation
                  (let ((fired nil))
                    (handler-case
                        (call-add-person stream (make-person :name "trigger-error" :id 2))
                      (error (e)
                        (setf fired t)
                        (unless (search "Simulated server-side error!" (format nil "~a" e))
                          (error "Wrong error message: ~a" e))))
                    (unless fired (error "Remote error was not signaled on client"))))
             (ignore-errors (usocket:socket-close sock))))
      (ignore-errors (usocket:socket-close server-socket))))
  (format t "      PASSED~%"))

;;; ---- Runner ----

(handler-case
    (progn
      (format t "~%")
      (test-varints)
      (test-field-skipping)
      (test-serialization-round-trip)
      (test-integration)
      (format t "~%All tests PASSED.~%")
      (sb-ext:exit :code 0))
  (error (e)
    (format t "~%FAILED: ~a~%" e)
    (sb-ext:exit :code 1)))
