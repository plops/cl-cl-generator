(eval-when (:compile-toplevel :execute :load-toplevel)
  (let ((current-dir (make-pathname :directory (pathname-directory *load-pathname*))))
    (push (merge-pathnames "../../" current-dir) asdf:*central-registry*))
  (ql:quickload '(:cl-cl-generator :flexi-streams :usocket)))

(defpackage :cl-cl-generator/example-grpc-gen
  (:use :cl :cl-cl-generator))

(in-package :cl-cl-generator/example-grpc-gen)

(defparameter *schema*
  '((:message phone-number
     ((:number :string 1)
      (:type :int32 2)))
    (:message person
     ((:name :string 1)
      (:id :int32 2)
      (:email :string 3)
      (:phones (:repeated phone-number) 4)))
    (:message address-book
     ((:people (:repeated person) 1)))
    (:message get-people-request
     ((:query :string 1)))
    (:service address-book-service
     ((:add-person person address-book)
      (:get-people get-people-request address-book)))))

(defparameter *output-dir*
  (merge-pathnames "source/"
                   (make-pathname :directory (pathname-directory *load-pathname*))))

(defun to-symbol (name)
  (intern (string-upcase (symbol-name name))))

(defun field-base-type (type)
  (if (and (consp type) (eq (car type) :repeated))
      (second type)
      type))

(defun is-repeated-p (type)
  (and (consp type) (eq (car type) :repeated)))

(defun extract-message-names (schema)
  (loop for entry in schema
        when (eq (first entry) :message)
        collect (second entry)))

(defun generate-struct (msg-name fields)
  `(defstruct ,msg-name
     ,@(loop for (f-name f-type f-num) in fields
             collect (let ((sym (to-symbol f-name))
                           (base (field-base-type f-type)))
                       (cond
                         ((is-repeated-p f-type)
                          `(,sym nil :type list))
                         ((eq base :int32)
                          `(,sym 0 :type integer))
                         ((eq base :bool)
                          `(,sym nil :type boolean))
                         ((eq base :string)
                          `(,sym "" :type string))
                         ((eq base :bytes)
                          `(,sym (make-array 0 :element-type '(unsigned-byte 8)) :type (simple-array (unsigned-byte 8) (*))))
                         (t
                          `(,sym nil)))))))

(defun generate-serializer (msg-name fields message-names)
  (let ((serializer-name (intern (format nil "SERIALIZE-~a" msg-name)))
        (body-forms nil))
    (dolist (field fields)
      (destructuring-bind (f-name f-type f-num) field
        (let* ((accessor (intern (format nil "~a-~a" msg-name (to-symbol f-name))))
               (base (field-base-type f-type))
               (repeated (is-repeated-p f-type)))
          (if repeated
              (push
               (cond
                 ((eq base :string)
                  `(dolist (elem (,accessor msg))
                     (write-string-field ,f-num elem stream)))
                 ((eq base :bytes)
                  `(dolist (elem (,accessor msg))
                     (write-bytes-field ,f-num elem stream)))
                 ((eq base :int32)
                  `(dolist (elem (,accessor msg))
                     (write-varint (logior (ash ,f-num 3) 0) stream)
                     (write-varint elem stream)))
                 ((eq base :bool)
                  `(dolist (elem (,accessor msg))
                     (write-varint (logior (ash ,f-num 3) 0) stream)
                     (write-varint (if elem 1 0) stream)))
                 ((member base message-names)
                  `(dolist (elem (,accessor msg))
                     (write-message-field ,f-num elem #',(intern (format nil "SERIALIZE-~a" base)) stream)))
                 (t (error "Unknown base type ~a" base)))
               body-forms)
              (push
               (cond
                 ((eq base :string)
                  `(write-string-field ,f-num (,accessor msg) stream))
                 ((eq base :bytes)
                  `(write-bytes-field ,f-num (,accessor msg) stream))
                 ((eq base :int32)
                  `(let ((val (,accessor msg)))
                     (unless (zerop val)
                       (write-varint (logior (ash ,f-num 3) 0) stream)
                       (write-varint val stream))))
                 ((eq base :bool)
                  `(let ((val (,accessor msg)))
                     (when val
                       (write-varint (logior (ash ,f-num 3) 0) stream)
                       (write-varint (if val 1 0) stream))))
                 ((member base message-names)
                  `(write-message-field ,f-num (,accessor msg) #',(intern (format nil "SERIALIZE-~a" base)) stream))
                 (t (error "Unknown base type ~a" base)))
               body-forms)))))
    `(defun ,serializer-name (msg stream)
       ,@(nreverse body-forms)
       msg)))

(defun generate-deserializer (msg-name fields message-names)
  (let ((deserializer-name (intern (format nil "DESERIALIZE-~a" msg-name)))
        (accum-vars nil)
        (accum-reverses nil)
        (cases nil))
    (dolist (field fields)
      (destructuring-bind (f-name f-type f-num) field
        (let* ((sym (to-symbol f-name))
               (accessor (intern (format nil "~a-~a" msg-name sym)))
               (base (field-base-type f-type))
               (repeated (is-repeated-p f-type)))
          (if repeated
              (let ((accum-var (intern (format nil "~a-ACCUM" sym))))
                (push `(,accum-var nil) accum-vars)
                (push `(setf (,accessor msg) (nreverse ,accum-var)) accum-reverses)
                (push
                 `(,f-num
                   (push
                    ,(cond
                       ((eq base :string) `(read-string-field stream))
                       ((eq base :bytes) `(read-bytes-field stream))
                       ((eq base :int32) `(read-varint stream))
                       ((eq base :bool) `(/= 0 (read-varint stream)))
                       ((member base message-names)
                        `(deserialize-nested stream #',(intern (format nil "DESERIALIZE-~a" base))))
                       (t (error "Unknown base type ~a" base)))
                    ,accum-var))
                 cases))
              (push
               `(,f-num
                 (setf (,accessor msg)
                       ,(cond
                          ((eq base :string) `(read-string-field stream))
                          ((eq base :bytes) `(read-bytes-field stream))
                          ((eq base :int32) `(read-varint stream))
                          ((eq base :bool) `(/= 0 (read-varint stream)))
                          ((member base message-names)
                           `(deserialize-nested stream #',(intern (format nil "DESERIALIZE-~a" base))))
                          (t (error "Unknown base type ~a" base)))))
               cases)))))
    `(defun ,deserializer-name (stream)
       (let ((msg (,(intern (format nil "MAKE-~a" msg-name))))
             ,@(nreverse accum-vars))
         (loop
           (let ((tag (read-varint stream nil nil)))
             (unless tag (return))
             (let ((field-number (ash tag -3))
                   (wire-type (logand tag 7)))
               (case field-number
                 ,@(nreverse cases)
                 (t (skip-field wire-type stream))))))
         ,@(nreverse accum-reverses)
         msg))))

(defun generate-package-exports (schema)
  (let ((exports nil))
    (loop for entry in schema
          do (case (first entry)
               (:message
                (let* ((msg-name (second entry))
                       (fields (third entry)))
                  (push msg-name exports)
                  (push (intern (format nil "MAKE-~a" msg-name)) exports)
                  (push (intern (format nil "SERIALIZE-~a" msg-name)) exports)
                  (push (intern (format nil "DESERIALIZE-~a" msg-name)) exports)
                  (dolist (f fields)
                    (let ((f-name (first f)))
                      (push (intern (format nil "~a-~a" msg-name (to-symbol f-name))) exports)))))
               (:service
                (let* ((service-name (second entry))
                       (methods (third entry)))
                  (push service-name exports)
                  (push (intern (format nil "DISPATCH-~a" service-name)) exports)
                  (push (intern (format nil "START-~a-SERVER" service-name)) exports)
                  (dolist (m methods)
                    (let ((m-name (first m)))
                      (push (to-symbol m-name) exports)
                      (push (intern (format nil "CALL-~a" m-name)) exports)))))))
    (nreverse exports)))

(defun generate-package (schema)
  (let ((exports (generate-package-exports schema)))
    `(toplevel
       (defpackage :protobuf-grpc-example
         (:use :cl)
         (:export ,@(loop for sym in exports
                          collect (intern (symbol-name sym) :keyword)))))))

(defun generate-messages (schema)
  (let ((msg-names (extract-message-names schema))
        (forms nil))
    (push `(in-package :protobuf-grpc-example) forms)
    
    (push '(defun write-varint (value stream)
            (let ((val (if (< value 0)
                           (ldb (byte 64 0) value)
                           value)))
              (loop
                (let ((byte (logand val #x7f)))
                  (setf val (ash val -7))
                  (if (zerop val)
                      (progn (write-byte byte stream) (return))
                      (write-byte (logior byte #x80) stream))))))
          forms)
          
    (push '(defun read-varint (stream &optional (eof-error-p t) eof-value)
            (let ((value 0)
                  (shift 0))
              (loop
                (let ((byte (read-byte stream (and eof-error-p (zerop shift)) nil)))
                  (unless byte
                    (if (zerop shift)
                        (return eof-value)
                        (error "Unexpected EOF in middle of varint")))
                  (setf value (logior value (ash (logand byte #x7f) shift)))
                  (when (zerop (logand byte #x80))
                    (return (if (logbitp 63 value)
                                (- value (ash 1 64))
                                value)))
                  (incf shift 7)))))
          forms)
          
    (push '(defun write-string-field (field-number value stream)
            (when (and value (string/= value ""))
              (let ((bytes (flexi-streams:string-to-octets value :external-format :utf-8)))
                (write-varint (logior (ash field-number 3) 2) stream)
                (write-varint (length bytes) stream)
                (write-sequence bytes stream))))
          forms)
          
    (push '(defun read-string-field (stream)
            (let* ((len (read-varint stream))
                   (bytes (make-array len :element-type '(unsigned-byte 8))))
              (read-sequence bytes stream)
              (flexi-streams:octets-to-string bytes :external-format :utf-8)))
          forms)

    (push '(defun write-bytes-field (field-number value stream)
            (when (and value (> (length value) 0))
              (write-varint (logior (ash field-number 3) 2) stream)
              (write-varint (length value) stream)
              (write-sequence value stream)))
          forms)

    (push '(defun read-bytes-field (stream)
            (let* ((len (read-varint stream))
                   (bytes (make-array len :element-type '(unsigned-byte 8))))
              (read-sequence bytes stream)
              bytes))
          forms)

    (push '(defun write-message-field (field-number msg serializer stream)
            (when msg
              (let ((bytes (flexi-streams:with-output-to-sequence (temp-stream)
                             (funcall serializer msg temp-stream))))
                (write-varint (logior (ash field-number 3) 2) stream)
                (write-varint (length bytes) stream)
                (write-sequence bytes stream))))
          forms)

    (push '(defun deserialize-nested (stream deserializer)
            (let* ((len (read-varint stream))
                   (bytes (make-array len :element-type '(unsigned-byte 8))))
              (read-sequence bytes stream)
              (with-open-stream (sub-stream (flexi-streams:make-in-memory-input-stream bytes))
                (funcall deserializer sub-stream))))
          forms)

    (push '(defun skip-field (wire-type stream)
            (case wire-type
              (0 (read-varint stream))
              (1 (loop repeat 8 do (read-byte stream)))
              (2 (let ((len (read-varint stream)))
                   (loop repeat len do (read-byte stream))))
              (5 (loop repeat 4 do (read-byte stream)))
              (t (error "Unknown wire type: ~a" wire-type))))
          forms)

    (loop for entry in schema
          when (eq (first entry) :message)
          do (push (generate-struct (second entry) (third entry)) forms))

    (loop for entry in schema
          when (eq (first entry) :message)
          do (push (generate-serializer (second entry) (third entry) msg-names) forms))

    (loop for entry in schema
          when (eq (first entry) :message)
          do (push (generate-deserializer (second entry) (third entry) msg-names) forms))

    `(toplevel ,@(nreverse forms))))

(defun generate-client-stub (m-name req-type resp-type)
  (let ((stub-name (intern (format nil "CALL-~a" m-name)))
        (serializer (intern (format nil "SERIALIZE-~a" req-type)))
        (deserializer (intern (format nil "DESERIALIZE-~a" resp-type)))
        (method-string (string-downcase (string m-name))))
    `(defun ,stub-name (stream request)
       (let* ((method-bytes (flexi-streams:string-to-octets ,method-string :external-format :utf-8))
              (payload-bytes (flexi-streams:with-output-to-sequence (s)
                               (,serializer request s))))
         (write-uint16 (length method-bytes) stream)
         (write-sequence method-bytes stream)
         (write-uint32 (length payload-bytes) stream)
         (write-sequence payload-bytes stream)
         (finish-output stream))
       (let ((status (read-byte stream)))
         (cond
           ((= status 1)
            (let* ((err-len (read-uint16 stream))
                   (err-bytes (make-array err-len :element-type '(unsigned-byte 8))))
              (read-sequence err-bytes stream)
              (error "Remote RPC error: ~a" (flexi-streams:octets-to-string err-bytes :external-format :utf-8))))
           ((= status 0)
            (let* ((payload-len (read-uint32 stream))
                   (payload-bytes (make-array payload-len :element-type '(unsigned-byte 8))))
              (read-sequence payload-bytes stream)
              (with-open-stream (s (flexi-streams:make-in-memory-input-stream payload-bytes))
                (,deserializer s))))
           (t (error "Invalid status byte: ~a" status)))))))

(defun generate-server-dispatch (service-name methods)
  (let ((dispatch-name (intern (format nil "DISPATCH-~a" service-name)))
        (cases nil))
    (dolist (m methods)
      (destructuring-bind (m-name req-type resp-type) m
        (let ((deserializer (intern (format nil "DESERIALIZE-~a" req-type)))
              (serializer (intern (format nil "SERIALIZE-~a" resp-type)))
              (method-string (string-downcase (string m-name)))
              (impl-method (to-symbol m-name)))
          (push
           `((string= method-name ,method-string)
             (let* ((req (,deserializer input-stream))
                    (resp (,impl-method impl req))
                    (resp-bytes (flexi-streams:with-output-to-sequence (s)
                                  (,serializer resp s))))
               (write-byte 0 output-stream)
               (write-uint32 (length resp-bytes) output-stream)
               (write-sequence resp-bytes output-stream)))
           cases))))
    `(defun ,dispatch-name (impl method-name input-stream output-stream)
       (handler-case
           (cond
             ,@(nreverse cases)
             (t (error "Unknown method: ~a" method-name)))
         (error (e)
           (let* ((err-msg (format nil "~a" e))
                  (err-bytes (flexi-streams:string-to-octets err-msg :external-format :utf-8)))
             (write-byte 1 output-stream)
             (write-uint16 (length err-bytes) output-stream)
             (write-sequence err-bytes output-stream))))
       (finish-output output-stream))))

(defun generate-service-interfaces (service-name methods)
  (let ((forms nil))
    (push `(defclass ,service-name () ()) forms)
    (dolist (m methods)
      (destructuring-bind (m-name req-type resp-type) m
        (declare (ignore req-type resp-type))
        (push `(defgeneric ,(to-symbol m-name) (impl request)) forms)))
    (nreverse forms)))

(defun generate-server-starter (service-name)
  (let ((starter-name (intern (format nil "START-~a-SERVER" service-name)))
        (dispatch-name (intern (format nil "DISPATCH-~a" service-name))))
    `(toplevel
       (defun ,(intern (format nil "HANDLE-~a-CLIENT" service-name)) (impl socket)
         (let ((stream (usocket:socket-stream socket)))
           (handler-case
               (loop
                 (let ((b1 (read-byte stream nil nil)))
                   (unless b1 (return))
                   (let* ((b2 (read-byte stream))
                          (method-len (logior (ash b1 8) b2))
                          (method-bytes (make-array method-len :element-type '(unsigned-byte 8))))
                     (read-sequence method-bytes stream)
                     (let* ((method-name (flexi-streams:octets-to-string method-bytes :external-format :utf-8))
                            (payload-len (read-uint32 stream))
                            (payload-bytes (make-array payload-len :element-type '(unsigned-byte 8))))
                       (read-sequence payload-bytes stream)
                       (with-open-stream (in-stream (flexi-streams:make-in-memory-input-stream payload-bytes))
                         (,dispatch-name impl method-name in-stream stream))))))
             (error (e)
               (declare (ignore e))))
           (ignore-errors (usocket:socket-close socket))))

       (defun ,starter-name (impl host port)
         (let ((server-socket (usocket:socket-listen host port :reuse-address t :element-type '(unsigned-byte 8))))
           (sb-thread:make-thread
            (lambda ()
              (unwind-protect
                   (loop
                     (handler-case
                         (let ((client-socket (usocket:socket-accept server-socket))
                               (handler-name (format nil "~a-client-handler" ',service-name)))
                           (sb-thread:make-thread
                            (lambda ()
                              (,(intern (format nil "HANDLE-~a-CLIENT" service-name)) impl client-socket))
                            :name handler-name))
                       (error () (return))))
                (ignore-errors (usocket:socket-close server-socket))))
            :name (format nil "~a-server-listener" ',service-name))
           server-socket)))))

(defun generate-network (schema)
  (let ((forms nil))
    (push `(in-package :protobuf-grpc-example) forms)

    (push '(defun write-uint16 (value stream)
            (write-byte (ldb (byte 8 8) value) stream)
            (write-byte (ldb (byte 8 0) value) stream))
          forms)

    (push '(defun read-uint16 (stream)
            (let ((b1 (read-byte stream))
                  (b2 (read-byte stream)))
              (logior (ash b1 8) b2)))
          forms)

    (push '(defun write-uint32 (value stream)
            (write-byte (ldb (byte 8 24) value) stream)
            (write-byte (ldb (byte 8 16) value) stream)
            (write-byte (ldb (byte 8 8) value) stream)
            (write-byte (ldb (byte 8 0) value) stream))
          forms)

    (push '(defun read-uint32 (stream)
            (let ((b1 (read-byte stream))
                  (b2 (read-byte stream))
                  (b3 (read-byte stream))
                  (b4 (read-byte stream)))
              (logior (ash b1 24) (ash b2 16) (ash b3 8) b4)))
          forms)

    (loop for entry in schema
          do (case (first entry)
               (:service
                (let ((service-name (second entry))
                      (methods (third entry)))
                  (dolist (form (generate-service-interfaces service-name methods))
                    (push form forms))
                  (dolist (m methods)
                    (push (generate-client-stub (first m) (second m) (third m)) forms))
                  (push (generate-server-dispatch service-name methods) forms)
                  (push (generate-server-starter service-name) forms)))))

    `(toplevel ,@(nreverse forms))))

(defun run-generator ()
  (ensure-directories-exist *output-dir*)

  ;; 1. Emit package.lisp
  (write-source "package" (generate-package *schema*) *output-dir*)

  ;; 2. Emit messages.lisp
  (write-source "messages" (generate-messages *schema*) *output-dir*)

  ;; 3. Emit network.lisp
  (write-source "network" (generate-network *schema*) *output-dir*)

  ;; 4. Emit protobuf-grpc-example.asd
  (let* ((asd-path (merge-pathnames "protobuf-grpc-example.asd" *output-dir*))
         (asd-code
           `(toplevel
              (asdf:defsystem :protobuf-grpc-example
                :version "0.1.0"
                :description "Protobuf and gRPC example generated by cl-cl-generator"
                :depends-on (:usocket :flexi-streams)
                :serial t
                :components ((:file "package")
                             (:file "messages")
                             (:file "network"))))))
    (ensure-directories-exist asd-path)
    (with-open-file (stream asd-path
                            :direction :output
                            :if-exists :supersede
                            :if-does-not-exist :create)
      (write-sequence (emit-cl asd-code) stream)))

  (format t "Successfully generated protobuf/gRPC code in ~a~%" *output-dir*))

(run-generator)
