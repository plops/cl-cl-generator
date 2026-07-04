(in-package :protobuf-grpc-example)

(defun write-varint (value stream)
  (let ((val
         (if (< value 0)
             (ldb (byte 64 0) value)
             value)))
    (loop
     (let ((byte (logand val 127)))
       (setf val (ash val -7))
       (if (zerop val)
           (progn
             (write-byte byte stream)
             (return))
           (write-byte (logior byte 128) stream))))))

(defun read-varint (stream &optional (eof-error-p t) eof-value)
  (let ((value 0) (shift 0))
    (loop
     (let ((byte (read-byte stream (and eof-error-p (zerop shift)) nil)))
       (unless byte
         (if (zerop shift)
             (return eof-value)
             (error "Unexpected EOF in middle of varint")))
       (setf value (logior value (ash (logand byte 127) shift)))
       (when (zerop (logand byte 128))
         (return
          (if (logbitp 63 value)
              (- value (ash 1 64))
              value)))
       (incf shift 7)))))

(defun write-string-field (field-number value stream)
  (when (and value (string/= value ""))
    (let ((bytes
           (flexi-streams:string-to-octets value :external-format :utf-8)))
      (write-varint (logior (ash field-number 3) 2) stream)
      (write-varint (length bytes) stream)
      (write-sequence bytes stream))))

(defun read-string-field (stream)
  (let* ((len (read-varint stream))
         (bytes (make-array len :element-type '(unsigned-byte 8))))
    (read-sequence bytes stream)
    (flexi-streams:octets-to-string bytes :external-format :utf-8)))

(defun write-bytes-field (field-number value stream)
  (when (and value (> (length value) 0))
    (write-varint (logior (ash field-number 3) 2) stream)
    (write-varint (length value) stream)
    (write-sequence value stream)))

(defun read-bytes-field (stream)
  (let* ((len (read-varint stream))
         (bytes (make-array len :element-type '(unsigned-byte 8))))
    (read-sequence bytes stream)
    bytes))

(defun write-message-field (field-number msg serializer stream)
  (when msg
    (let ((bytes
           (flexi-streams:with-output-to-sequence (temp-stream)
             (funcall serializer msg temp-stream))))
      (write-varint (logior (ash field-number 3) 2) stream)
      (write-varint (length bytes) stream)
      (write-sequence bytes stream))))

(defun deserialize-nested (stream deserializer)
  (let* ((len (read-varint stream))
         (bytes (make-array len :element-type '(unsigned-byte 8))))
    (read-sequence bytes stream)
    (with-open-stream
        (sub-stream (flexi-streams:make-in-memory-input-stream bytes))
      (funcall deserializer sub-stream))))

(defun skip-field (wire-type stream)
  (case wire-type
    (0 (read-varint stream))
    (1
     (loop repeat 8
           do (read-byte stream)))
    (2
     (let ((len (read-varint stream)))
       (loop repeat len
             do (read-byte stream))))
    (5
     (loop repeat 4
           do (read-byte stream)))
    (t (error "Unknown wire type: ~a" wire-type))))

(defstruct phone-number (number "" :type string) (type 0 :type integer))

(defstruct person
  (name "" :type string)
  (id 0 :type integer)
  (email "" :type string)
  (phones nil :type list))

(defstruct address-book (people nil :type list))

(defstruct get-people-request (query "" :type string))

(defun serialize-phone-number (msg stream)
  (write-string-field 1 (phone-number-number msg) stream)
  (let ((val (phone-number-type msg)))
    (unless (zerop val)
      (write-varint (logior (ash 2 3) 0) stream)
      (write-varint val stream)))
  msg)

(defun serialize-person (msg stream)
  (write-string-field 1 (person-name msg) stream)
  (let ((val (person-id msg)))
    (unless (zerop val)
      (write-varint (logior (ash 2 3) 0) stream)
      (write-varint val stream)))
  (write-string-field 3 (person-email msg) stream)
  (dolist (elem (person-phones msg))
    (write-message-field 4 elem #'serialize-phone-number stream))
  msg)

(defun serialize-address-book (msg stream)
  (dolist (elem (address-book-people msg))
    (write-message-field 1 elem #'serialize-person stream))
  msg)

(defun serialize-get-people-request (msg stream)
  (write-string-field 1 (get-people-request-query msg) stream)
  msg)

(defun deserialize-phone-number (stream)
  (let ((msg (make-phone-number)))
    (loop
     (let ((tag (read-varint stream nil nil)))
       (unless tag
         (return))
       (let ((field-number (ash tag -3)) (wire-type (logand tag 7)))
         (case field-number
           (1 (setf (phone-number-number msg) (read-string-field stream)))
           (2 (setf (phone-number-type msg) (read-varint stream)))
           (t (skip-field wire-type stream))))))
    msg))

(defun deserialize-person (stream)
  (let ((msg (make-person)) (phones-accum nil))
    (loop
     (let ((tag (read-varint stream nil nil)))
       (unless tag
         (return))
       (let ((field-number (ash tag -3)) (wire-type (logand tag 7)))
         (case field-number
           (1 (setf (person-name msg) (read-string-field stream)))
           (2 (setf (person-id msg) (read-varint stream)))
           (3 (setf (person-email msg) (read-string-field stream)))
           (4
            (push (deserialize-nested stream #'deserialize-phone-number)
                  phones-accum))
           (t (skip-field wire-type stream))))))
    (setf (person-phones msg) (nreverse phones-accum))
    msg))

(defun deserialize-address-book (stream)
  (let ((msg (make-address-book)) (people-accum nil))
    (loop
     (let ((tag (read-varint stream nil nil)))
       (unless tag
         (return))
       (let ((field-number (ash tag -3)) (wire-type (logand tag 7)))
         (case field-number
           (1
            (push (deserialize-nested stream #'deserialize-person)
                  people-accum))
           (t (skip-field wire-type stream))))))
    (setf (address-book-people msg) (nreverse people-accum))
    msg))

(defun deserialize-get-people-request (stream)
  (let ((msg (make-get-people-request)))
    (loop
     (let ((tag (read-varint stream nil nil)))
       (unless tag
         (return))
       (let ((field-number (ash tag -3)) (wire-type (logand tag 7)))
         (case field-number
           (1 (setf (get-people-request-query msg) (read-string-field stream)))
           (t (skip-field wire-type stream))))))
    msg))