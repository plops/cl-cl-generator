# Implementation Plan: Protobuf & gRPC Common Lisp Code Generator Example

This document outlines the design and implementation strategy for building a subset of Protobuf-inspired message serialization and gRPC-like client/server networking in Common Lisp, generated entirely via [cl-cl-generator](file:///workspace/src/cl-cl-generator/cl.lisp).

> [!IMPORTANT]
> **Compatibility Note**: This protocol is *conceptually informed* by Protobuf and gRPC to demonstrate code generation. It is **not** wire-compatible with standard Google Protobuf compilers (`protoc`) or standard HTTP/2-based gRPC libraries. It uses a custom TCP framing protocol and a Lisp S-expression schema DSL.

---

## 1. Objectives

- **Transpilation Demonstration**: Demonstrate the power of [cl-cl-generator](file:///workspace/src/cl-cl-generator/cl.lisp) to dynamically generate Lisp structures, custom serializers/deserializers, client stubs, and server routing loops.
- **Protobuf Wire Format Subset**: 
  - Support Varint (`wire-type` 0) for `:int32` and `:bool`.
  - Support Length-Delimited (`wire-type` 2) for `:string`, `:bytes`, nested messages, and repeated fields (unpacked).
  - Robust deserialization that skips unknown tag numbers according to their wire type.
- **gRPC TCP Framing Subset**:
  - Simple client-server TCP framing using `:usocket` and `:flexi-streams`.
  - Multi-threaded connection handling (using `sb-thread` under SBCL).
  - Clean error reporting for remote exceptions.

---

## 2. DSL / Schema Specification

We will define the messages and services using a clean, Lisp S-expression layout:

```lisp
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
```

---

## 3. Code Generation Strategy

The generator script [gen.lisp](file:///workspace/src/cl-cl-generator/example/09_protobuf_grpc/gen.lisp) will write three target files:

### A. package.lisp
Declares package `:protobuf-grpc-example` and exports:
- Message structure names and accessors.
- Message serialization/deserialization functions.
- Client calling stub functions.
- Server implementation generic functions and server starter functions.

### B. messages.lisp
Contains:
1. **Message Structs**: Generated via `defstruct`.
2. **Core Binary Helpers**:
   - `write-varint` / `read-varint`
   - `write-string-field` / `read-string-field`
   - `skip-field` (wire-type skipper for forward compatibility)
3. **Serializers**: `serialize-<message-name> (msg stream)`
4. **Deserializers**: `deserialize-<message-name> (stream)`

### C. network.lisp
Contains:
1. **Framing Helpers**:
   - `write-uint16` / `read-uint16`
   - `write-uint32` / `read-uint32`
2. **Client Stubs**: `call-<method-name> (stream request)`
3. **Server Framework**:
   - `dispatch-<service-name> (impl method-name input-stream output-stream)`
   - `start-<service-name>-server (impl host port)`
   - Abstract generic functions for service implementation methods.

---

## 4. Architectural Details

### Varint Serialization & Deserialization
```lisp
(defun write-varint (value stream)
  (let ((val (if (< value 0)
                 (ldb (byte 64 0) value)
                 value)))
    (loop
      (let ((byte (logand val #x7f)))
        (setf val (ash val -7))
        (if (zerop val)
            (progn (write-byte byte stream) (return))
            (write-byte (logior byte #x80) stream))))))

(defun read-varint (stream)
  (let ((value 0)
        (shift 0))
    (loop
      (let ((byte (read-byte stream nil nil)))
        (unless byte (error "Unexpected EOF reading varint"))
        (setf value (logior value (ash (logand byte #x7f) shift)))
        (when (zerop (logand byte #x80))
          ;; Convert 64-bit two's complement back to standard Lisp signed integer
          (return (if (logbitp 63 value)
                      (- value (ash 1 64))
                      value)))
        (incf shift 7)))))
```

### TCP Framing Protocol
- **Request Frame**:
  - `Method Name Length` (2 bytes, big-endian)
  - `Method Name` (UTF-8 encoded string)
  - `Payload Length` (4 bytes, big-endian)
  - `Payload` (serialized request bytes)
- **Response Frame**:
  - `Status` (1 byte: 0 for success, 1 for error)
  - `Error Message Length` (2 bytes, only if status = 1)
  - `Error Message` (UTF-8 string, only if status = 1)
  - `Payload Length` (4 bytes, only if status = 0)
  - `Payload` (serialized response bytes, only if status = 0)

---

## 5. Verification & Testing

To ensure correctness and catch regressions, we will implement both a unit test suite and an integration test.

### 5.1 Unit Test Suite
We will generate a unit test file `run_tests.lisp` that targets the serialization and decoding layers directly without networking dependencies. It will test:
1. **Varint Encoding/Decoding**:
   - Edge values: `0`, positive numbers near single-byte and multi-byte boundaries (e.g., `127`, `128`, `16383`, `16384`), and large `int32` integers.
   - Standard negative integer encoding representation in two's complement.
2. **Field Skipping**:
   - Verify `skip-field` behavior. Test deserialization of a byte array that contains a combination of known and unknown tags to ensure unknown tags are skipped properly while preserving correct values for known tags.
3. **Serialization Completeness**:
   - Encode a sample message (`Person`) with mixed types, nested messages, and empty lists.
   - Deserialize it and assert structural equality (using `equalp` or custom comparators) between the original message and the round-tripped message.

### 5.2 Integration Test
The integration test suite will verify the client-server layer over a local TCP loopback using `usocket`:
1. Start the server (with mock service implementations) in a background thread.
2. Perform RPC requests (`AddPerson` and `GetPeople`) using client stubs.
3. Intentionally trigger exceptions/failures on the server and check that the client correctly receives the RPC status errors.
4. Cleanly terminate the TCP socket connections and the background server thread.

---

## 6. Document References

To implement this plan quickly and accurately, the implementing agent should consult:
- **Transpiler Library Core**: [cl.lisp](file:///workspace/src/cl-cl-generator/cl.lisp)
- **Transpiler Code Generation Guide**: [SKILL.md](file:///workspace/src/cl-cl-generator/.agents/skills/cl-cl-generator/SKILL.md)
- **Transpiler Test Suite**: [tests.lisp](file:///workspace/src/cl-cl-generator/tests.lisp)
- **Standard Generator Pattern**: [example/00_test/gen.lisp](file:///workspace/src/cl-cl-generator/example/00_test/gen.lisp)
- **Multi-File Generator Pattern**: [example/08_expanse_combat/gen.lisp](file:///workspace/src/cl-cl-generator/example/08_expanse_combat/gen.lisp)
