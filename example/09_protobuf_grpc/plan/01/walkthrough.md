# Walkthrough: Implementing `09_protobuf_grpc`

This document traces the step-by-step implementation of the `09_protobuf_grpc` example using `cl-cl-generator`. It records design decisions made during development and how they map to the plan.

---

## Step 1: Reading the Plan and Referenced Materials

The implementation started by reading:
- `plan/01/implementation_plan.md` — defined the schema DSL, the three output files, and the wire protocol layout.
- `SKILL.md` for `cl-cl-generator` — explained the `toplevel`, `comment`, `raw` keywords and how `,@(loop ...)` splicing works inside backquoted templates.
- `example/00_test/gen.lisp` — the simplest single-file generator pattern.
- `example/08_expanse_combat/gen.lisp` + `01_package.lisp` — the multi-file generator pattern with an orchestrator calling `write-source` multiple times.
- `cl.lisp` — confirmed the public API: `emit-cl` and `write-source`.

**Key lesson from SKILL.md**: Because the generator and the target language are both Common Lisp, templates must use `eval-when` to eagerly `quickload` any package whose symbols appear at read-time inside backquoted template forms. Failing to do this causes a `Package XYZ does not exist` reader error before any code runs.

---

## Step 2: Initial gen.lisp — Read-time Package Error

The first version of `gen.lisp` quickloaded only `:cl-cl-generator`. When the file was loaded by SBCL, the reader hit `flexi-streams:string-to-octets` inside a backquoted template body and crashed:

```
Package FLEXI-STREAMS does not exist.
  Line: 245, Column: 58
```

**Fix**: Add `:flexi-streams` and `:usocket` to the `ql:quickload` list inside the `eval-when` block:

```lisp
(eval-when (:compile-toplevel :execute :load-toplevel)
  (let ((current-dir (make-pathname :directory (pathname-directory *load-pathname*))))
    (push (merge-pathnames "../../" current-dir) asdf:*central-registry*))
  (ql:quickload '(:cl-cl-generator :flexi-streams :usocket)))
```

This is SKILL.md §3: *"Preventing Reader Package Errors"*. Always `quickload` every package whose symbols appear literally inside any form in the file, even if they live only in backquoted (unevaluated) templates — the reader interns those symbols before evaluation occurs.

---

## Step 3: Code Generation Architecture

`gen.lisp` defines helper functions that build S-expression trees, then calls `write-source` three times:

### Helper Function Pattern

Each section of generated code is produced by a dedicated builder function:

| Function | Output |
|---|---|
| `generate-package` | `package.lisp` — `defpackage` with all exports |
| `generate-messages` | `messages.lisp` — helpers + structs + serializers + deserializers |
| `generate-network` | `network.lisp` — framing + client stubs + dispatch + server |

Each builder loops over the `*schema*` list using standard CL `loop`/`dolist` and `push` to accumulate forms, then wraps the result in `` `(toplevel ,@(nreverse forms)) ``.

### Symbol Naming Convention

All generated symbol names follow a strict convention derived from the schema:

| Pattern | Example |
|---|---|
| Struct type | `person` |
| Constructor | `make-person` |
| Accessor | `person-name`, `person-id` |
| Serializer | `serialize-person` |
| Deserializer | `deserialize-person` |
| Client stub | `call-add-person` |
| Dispatcher | `dispatch-address-book-service` |
| Server starter | `start-address-book-service-server` |
| Client handler | `handle-address-book-service-client` (internal) |

Symbols are built at generation-time using `intern` + `format nil`:

```lisp
(intern (format nil "SERIALIZE-~a" msg-name))
```

---

## Step 4: Varint Implementation

The varint functions are injected as literal quoted forms (not backquoted with splicing) because they are purely static — they don't depend on the schema at all:

```lisp
(push '(defun write-varint (value stream) ...) forms)
```

This avoids the need to double-escape backquotes and keeps the generator readable.

**Two's complement negative integers**: `write-varint` converts negative values to their 64-bit two's complement unsigned representation with `(ldb (byte 64 0) value)` before encoding. `read-varint` reverses this with `(logbitp 63 value)` → subtract `(ash 1 64)`.

---

## Step 5: Serialization — Default Value Elision

For scalar non-repeated fields, the serializer elides the field when it holds the default value (matching protobuf3 behaviour):
- `:int32` / `:bool` fields are only written when non-zero / non-nil.
- `:string` fields are only written when non-empty.

```lisp
;; int32: skip zero
(let ((val (person-id msg)))
  (unless (zerop val)
    (write-varint (logior (ash 2 3) 0) stream)
    (write-varint val stream)))

;; string: skip empty
(write-string-field 1 (person-name msg) stream)
;; write-string-field internally: (when (and value (string/= value "")) ...)
```

This keeps the wire representation compact and matches the semantics of protobuf3.

---

## Step 6: Deserializer — Unknown Field Skipping

`skip-field` enables forward compatibility: a deserializer reading a message from a newer writer that has added new fields will ignore those fields without corrupting subsequent fields.

The tag byte encodes both the field number (upper bits) and the wire type (lower 3 bits). For each tag, the deserializer inspects only the field number against a `case` form; any unknown field number falls to the `t` branch and calls `skip-field` with the wire type:

```lisp
(t (skip-field wire-type stream))
```

`skip-field` advances the stream by the right number of bytes for each wire type:

| Wire type | Meaning | Skip action |
|---|---|---|
| 0 | Varint | `read-varint` (consume variable bytes) |
| 1 | 64-bit fixed | read 8 bytes |
| 2 | Length-delimited | `read-varint` for length, then read that many bytes |
| 5 | 32-bit fixed | read 4 bytes |

Wire types 3 and 4 (start/end group — deprecated in protobuf3) are treated as errors.

---

## Step 7: Network Framing Protocol

The TCP framing protocol was designed to be simple and self-delimiting. Each request frame contains:

```
[2 bytes] method name length   (big-endian uint16)
[N bytes] method name          (UTF-8)
[4 bytes] payload length       (big-endian uint32)
[M bytes] payload              (serialized request)
```

The response frame contains one of:

```
Success:
[1 byte ] status = 0
[4 bytes] payload length  (big-endian uint32)
[M bytes] payload         (serialized response)

Error:
[1 byte ] status = 1
[2 bytes] error message length  (big-endian uint16)
[K bytes] error message         (UTF-8)
```

**Design decision — why not HTTP/2?** The plan explicitly chose a minimal custom TCP framing to demonstrate `cl-cl-generator`'s code generation capabilities without the complexity of implementing or depending on an HTTP/2 stack. The framing is sufficient to demonstrate method routing, binary payload transport, and error propagation over a network socket.

---

## Step 8: Server — Multi-threaded Connection Handling

`start-address-book-service-server` returns immediately, having spawned a single listener thread. That listener loop calls `usocket:socket-accept` and spawns one new `sb-thread` per accepted connection:

```
main thread
  └─ listener thread (blocking loop on socket-accept)
        └─ client thread 1 (handle-address-book-service-client)
        └─ client thread 2 ...
```

`unwind-protect` around the listener loop ensures `usocket:socket-close` on the server socket is called even if an exception escapes the accept loop. `ignore-errors` protects the `socket-close` call itself in case the socket is already closed.

---

## Step 9: Error Handling Flow

The error handling has three distinct layers:

1. **Server dispatch** (`dispatch-address-book-service`): Wraps the entire `cond` dispatch in `handler-case`. Any `error` condition raised by the service implementation — or by an unknown method name — is caught, serialized into a UTF-8 error string, and sent back as a status=1 response frame. The server **never crashes** due to business-logic errors.

2. **Client stubs** (`call-add-person`, `call-get-people`): Read the status byte. If `status = 1`, they read the error string and re-raise it as a standard CL `error`. If the status byte is anything other than 0 or 1, a separate error is raised for the invalid framing.

3. **Per-connection handler** (`handle-address-book-service-client`): Wraps the read loop in `handler-case`. Any unrecoverable I/O error (e.g. `end-of-file` from a client disconnecting mid-frame) silently terminates the handler loop and closes the socket — it does not crash the server thread or the listener thread.

---

## Step 10: Run Scripts — Gitignore Constraint

The `.gitignore` for this repository contains `example/**/run_*.lisp`. This means the natural name `run_tests.lisp` would be silently ignored by git. The solution was to:
- Name the loadable Lisp files `tests_runner.lisp` and `demo_runner.lisp` (not matching the gitignore pattern).
- Create thin shell wrapper scripts `run_tests.sh` and `run_demo.sh` that call `sbcl --load` on those files.
- A third script `run_gen.sh` re-runs code generation.

An earlier attempt to inline all the Lisp code inside a single `sbcl --eval "..."` call failed with **"Multiple expressions in --eval option"** — SBCL's `--eval` flag accepts exactly one top-level expression per invocation. Loading a file is the correct approach.

---

## Summary of Files Created

```
example/09_protobuf_grpc/
├── gen.lisp               # Code generator (source of truth)
├── tests_runner.lisp      # Unit + integration test suite
├── demo_runner.lisp       # Live demonstration script
├── run_gen.sh             # Shell: regenerate source/
├── run_tests.sh           # Shell: run test suite
├── run_demo.sh            # Shell: live demo
└── source/
    ├── protobuf-grpc-example.asd   # ASDF system definition
    ├── package.lisp                 # Package + exports
    ├── messages.lisp                # Structs + serializers + deserializers
    └── network.lisp                 # Framing + client stubs + server
```
