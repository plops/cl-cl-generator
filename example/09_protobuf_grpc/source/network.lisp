(in-package :protobuf-grpc-example)

(defun write-uint16 (value stream)
  (write-byte (ldb (byte 8 8) value) stream)
  (write-byte (ldb (byte 8 0) value) stream))

(defun read-uint16 (stream)
  (let ((b1 (read-byte stream)) (b2 (read-byte stream)))
    (logior (ash b1 8) b2)))

(defun write-uint32 (value stream)
  (write-byte (ldb (byte 8 24) value) stream)
  (write-byte (ldb (byte 8 16) value) stream)
  (write-byte (ldb (byte 8 8) value) stream)
  (write-byte (ldb (byte 8 0) value) stream))

(defun read-uint32 (stream)
  (let ((b1 (read-byte stream)) (b2 (read-byte stream)) (b3 (read-byte stream))
        (b4 (read-byte stream)))
    (logior (ash b1 24) (ash b2 16) (ash b3 8) b4)))

(defclass address-book-service ()
  nil)

(defgeneric add-person (impl request))

(defgeneric get-people (impl request))

(defun call-add-person (stream request)
  (let* ((method-bytes
          (flexi-streams:string-to-octets "add-person" :external-format
                                          :utf-8))
         (payload-bytes
          (flexi-streams:with-output-to-sequence (s)
            (serialize-person request s))))
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
         (error "Remote RPC error: ~a"
                (flexi-streams:octets-to-string err-bytes :external-format
                                                :utf-8))))
      ((= status 0)
       (let* ((payload-len (read-uint32 stream))
              (payload-bytes
               (make-array payload-len :element-type '(unsigned-byte 8))))
         (read-sequence payload-bytes stream)
         (with-open-stream
             (s (flexi-streams:make-in-memory-input-stream payload-bytes))
           (deserialize-address-book s))))
      (t (error "Invalid status byte: ~a" status)))))

(defun call-get-people (stream request)
  (let* ((method-bytes
          (flexi-streams:string-to-octets "get-people" :external-format
                                          :utf-8))
         (payload-bytes
          (flexi-streams:with-output-to-sequence (s)
            (serialize-get-people-request request s))))
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
         (error "Remote RPC error: ~a"
                (flexi-streams:octets-to-string err-bytes :external-format
                                                :utf-8))))
      ((= status 0)
       (let* ((payload-len (read-uint32 stream))
              (payload-bytes
               (make-array payload-len :element-type '(unsigned-byte 8))))
         (read-sequence payload-bytes stream)
         (with-open-stream
             (s (flexi-streams:make-in-memory-input-stream payload-bytes))
           (deserialize-address-book s))))
      (t (error "Invalid status byte: ~a" status)))))

(defun dispatch-address-book-service (impl method-name input-stream
                                      output-stream)
  (handler-case (cond
                  ((string= method-name "add-person")
                   (let* ((req (deserialize-person input-stream))
                          (resp (add-person impl req))
                          (resp-bytes
                           (flexi-streams:with-output-to-sequence (s)
                             (serialize-address-book resp s))))
                     (write-byte 0 output-stream)
                     (write-uint32 (length resp-bytes) output-stream)
                     (write-sequence resp-bytes output-stream)))
                  ((string= method-name "get-people")
                   (let* ((req (deserialize-get-people-request input-stream))
                          (resp (get-people impl req))
                          (resp-bytes
                           (flexi-streams:with-output-to-sequence (s)
                             (serialize-address-book resp s))))
                     (write-byte 0 output-stream)
                     (write-uint32 (length resp-bytes) output-stream)
                     (write-sequence resp-bytes output-stream)))
                  (t (error "Unknown method: ~a" method-name)))
    (error (e)
           (let* ((err-msg (format nil "~a" e))
                  (err-bytes
                   (flexi-streams:string-to-octets err-msg :external-format
                                                   :utf-8)))
             (write-byte 1 output-stream)
             (write-uint16 (length err-bytes) output-stream)
             (write-sequence err-bytes output-stream))))
  (finish-output output-stream))

(defun handle-address-book-service-client (impl socket)
  (let ((stream (usocket:socket-stream socket)))
    (handler-case (loop
                   (let ((b1 (read-byte stream nil nil)))
                     (unless b1
                       (return))
                     (let* ((b2 (read-byte stream))
                            (method-len (logior (ash b1 8) b2))
                            (method-bytes
                             (make-array method-len :element-type
                                         '(unsigned-byte 8))))
                       (read-sequence method-bytes stream)
                       (let* ((method-name
                               (flexi-streams:octets-to-string method-bytes
                                                               :external-format
                                                               :utf-8))
                              (payload-len (read-uint32 stream))
                              (payload-bytes
                               (make-array payload-len :element-type
                                           '(unsigned-byte 8))))
                         (read-sequence payload-bytes stream)
                         (with-open-stream
                             (in-stream
                              (flexi-streams:make-in-memory-input-stream
                               payload-bytes))
                           (dispatch-address-book-service impl method-name
                            in-stream stream))))))
      (error (e) (declare (ignore e))))
    (ignore-errors (usocket:socket-close socket))))

(defun start-address-book-service-server (impl host port)
  (let ((server-socket
         (usocket:socket-listen host port :reuse-address t :element-type
                                '(unsigned-byte 8))))
    (sb-thread:make-thread
     (lambda ()
       (unwind-protect (loop
                        (handler-case (let ((client-socket
                                             (usocket:socket-accept
                                              server-socket))
                                            (handler-name
                                             (format nil "~a-client-handler"
                                                     'address-book-service)))
                                        (sb-thread:make-thread
                                         (lambda ()
                                           (handle-address-book-service-client
                                            impl client-socket))
                                         :name handler-name))
                          (error nil (return))))
         (ignore-errors (usocket:socket-close server-socket))))
     :name (format nil "~a-server-listener" 'address-book-service))
    server-socket))