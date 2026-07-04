;;;; demo_runner.lisp — Live demonstration of protobuf-grpc-example
;;;; Starts a server, connects a client, performs RPC calls, shows error propagation.

(eval-when (:compile-toplevel :execute :load-toplevel)
  (let ((current-dir (make-pathname :directory (pathname-directory *load-pathname*))))
    (push (merge-pathnames "source/" current-dir) asdf:*central-registry*))
  (ql:quickload '(:protobuf-grpc-example :usocket :flexi-streams) :silent t))

(defpackage :protobuf-grpc-example/demo
  (:use :cl :protobuf-grpc-example))

(in-package :protobuf-grpc-example/demo)

;;; ---- Service Implementation ----

(defclass demo-service (address-book-service)
  ((db :accessor service-db :initform (make-address-book))))

(defmethod add-person ((impl demo-service) (req person))
  (when (string= (person-name req) "trigger-error")
    (error "Simulated server-side error!"))
  (format t "  [SERVER] AddPerson: ~a (id=~a, email=~a, ~a phone(s))~%"
          (person-name req) (person-id req) (person-email req)
          (length (person-phones req)))
  (push req (address-book-people (service-db impl)))
  (service-db impl))

(defmethod get-people ((impl demo-service) (req get-people-request))
  (format t "  [SERVER] GetPeople: query=~s~%" (get-people-request-query req))
  (let ((query (get-people-request-query req))
        (res   (make-address-book)))
    (dolist (p (address-book-people (service-db impl)))
      (when (or (string= query "") (search query (person-name p)))
        (push p (address-book-people res))))
    res))

;;; ---- Demo ----

(defun print-book (book label)
  (format t "  [CLIENT] ~a — ~a person(s):~%" label (length (address-book-people book)))
  (dolist (p (address-book-people book))
    (format t "           * ~a (id=~a, email=~a, ~a phone(s))~%"
            (person-name p) (person-id p) (person-email p)
            (length (person-phones p)))))

(handler-case
    (let* ((impl          (make-instance 'demo-service))
           (port          50052)
           (server-socket (start-address-book-service-server impl "127.0.0.1" port)))
      (format t "~%Server started on 127.0.0.1:~a~%~%" port)
      (sleep 0.3)

      (let* ((sock   (usocket:socket-connect "127.0.0.1" port :element-type '(unsigned-byte 8)))
             (stream (usocket:socket-stream sock)))

        ;; ---- 1. AddPerson: Alice ----
        (format t "[CLIENT] AddPerson: Alice (id=1, 2 phones)~%")
        (let* ((alice (make-person
                        :name  "Alice"
                        :id    1
                        :email "alice@example.com"
                        :phones (list (make-phone-number :number "+1-555-0101" :type 0)
                                      (make-phone-number :number "+1-555-0102" :type 1))))
               (book (call-add-person stream alice)))
          (print-book book "Response"))
        (format t "~%")

        ;; ---- 2. AddPerson: Bob ----
        (format t "[CLIENT] AddPerson: Bob (id=2, 1 phone)~%")
        (let* ((bob (make-person
                      :name  "Bob"
                      :id    2
                      :email "bob@example.com"
                      :phones (list (make-phone-number :number "+1-555-0200" :type 0))))
               (book (call-add-person stream bob)))
          (print-book book "Response"))
        (format t "~%")

        ;; ---- 3. AddPerson: Charlie ----
        (format t "[CLIENT] AddPerson: Charlie (id=3, no phones)~%")
        (let* ((charlie (make-person :name "Charlie" :id 3 :email "charlie@example.com"))
               (book (call-add-person stream charlie)))
          (print-book book "Response"))
        (format t "~%")

        ;; ---- 4. GetPeople: all ----
        (format t "[CLIENT] GetPeople: query=\"\" (all)~%")
        (let ((book (call-get-people stream (make-get-people-request :query ""))))
          (print-book book "Response"))
        (format t "~%")

        ;; ---- 5. GetPeople: filtered ----
        (format t "[CLIENT] GetPeople: query=\"Bob\"~%")
        (let ((book (call-get-people stream (make-get-people-request :query "Bob"))))
          (print-book book "Response"))
        (format t "~%")

        ;; ---- 6. GetPeople: no match ----
        (format t "[CLIENT] GetPeople: query=\"Zephyr\" (no match expected)~%")
        (let ((book (call-get-people stream (make-get-people-request :query "Zephyr"))))
          (print-book book "Response"))
        (format t "~%")

        ;; ---- 7. Remote error propagation ----
        (format t "[CLIENT] AddPerson: name=\"trigger-error\" — demonstrating error propagation~%")
        (handler-case
            (call-add-person stream (make-person :name "trigger-error" :id 99))
          (error (e)
            (format t "  [SERVER] Raises error -> client receives:~%")
            (format t "  [CLIENT] Remote RPC error caught: ~a~%~%" e)))

        (ignore-errors (usocket:socket-close sock)))

      (ignore-errors (usocket:socket-close server-socket))
      (format t "Demo complete. Server shut down.~%")
      (sb-ext:exit :code 0))
  (error (e)
    (format t "Demo failed: ~a~%" e)
    (sb-ext:exit :code 1)))
