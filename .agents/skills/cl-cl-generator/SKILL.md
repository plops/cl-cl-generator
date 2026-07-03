---
name: cl-cl-generator
description: Provides documentation and guidelines for using the cl-cl-generator S-expression code generator. Explains how to construct Common Lisp code dynamically, write helper macros/functions, and use generation-time loops (,@(loop ...)) to reduce boilerplate.
---

# CL-CL-Generator System Documentation

This skill explains how to write Common Lisp code using `cl-cl-generator` S-expression templates. Since the generator language and the target language are both Common Lisp, the transpiler acts as a formatting printer that understands S-expression structures, code layout, comments, and file caching.

## Core API

The package `:cl-cl-generator` exports:
- `emit-cl` : Converts an S-expression form into a formatted Common Lisp code string.
- `write-source` : Takes a filename, an S-expression form, and an optional directory, and writes the formatted code to a file. It uses `sxhash` hashing to avoid touching the file's modification time (mtime) if the contents are identical.

## DSL Keywords

While standard Common Lisp constructs (like `defun`, `let`, `cond`, `loop`, `if`, etc.) write exactly as-is, the generator provides a few special keywords:

1. **`toplevel` / `do0`**
   - Groups a list of forms to be written one after another without outer parentheses.
   - Example: `(toplevel (in-package :cl-user) (defun f () 1))`
   - Emits:
     ```lisp
     (in-package :cl-user)

     (defun f ()
       1)
     ```

2. **`comment` / `comments`**
   - Renders single or multi-line comments.
   - Example: `(comment "Calculate square")`
   - Emits: `;; Calculate square` (indented automatically to match the surrounding block).

3. **`raw`**
   - Inserts raw unquoted text directly into the code (e.g. for reader conditionals or custom literals).
   - Example: `(raw "#+sbcl")`
   - Emits: `#+sbcl`

---

## Reducing Boilerplate with Generation-Time Evaluation

The true power of this generator comes from Lisp's standard list processing. Because the generator code is constructed inside a backquote (\`), you can evaluate normal Lisp code at generation time using comma (`,`) and comma-splice (`,@`) to build S-expressions dynamically.

### 1. Generating S-Expressions in a Loop (`,@(loop ...)`)
When you need to define multiple functions, structures, or properties that share a pattern, use `,@(loop ...)` to collect and splice S-expression forms at generation-time.

#### Example:
Instead of writing multiple similar metric helpers:
```lisp
(defun distance-x (a b) (abs (- (x a) (x b))))
(defun distance-y (a b) (abs (- (y a) (y b))))
(defun distance-z (a b) (abs (- (z a) (z b))))
```
Write a loop inside your S-expression template:
```lisp
`(toplevel
   ,@(loop for axis in '(x y z)
           collect
           `(defun ,(intern (format nil "DISTANCE-~a" axis)) (a b)
              (abs (- (,axis a) (,axis b))))))
```

This generates three clean, fully-compiled, and formatted functions in the output file without manual repetition.

### 2. Helper Functions (S-Expression Builders)
Define normal Lisp helper functions to wrap repetitive code patterns. Because templates are backquoted, you **must** call these functions with a leading comma (`,`) so they evaluate at generation-time and insert their returned S-expressions.

#### Example:
Define a builder for defining safe mathematical dividers:
```lisp
(defun make-safe-divider (name divisor-limit)
  `(defun ,name (numerator denominator)
     (cond
       ((< (abs denominator) ,divisor-limit)
        (comment "Avoid division by zero")
        nil)
       (t (/ numerator denominator)))))
```

Then, call it in your generator template:
```lisp
(write-source "math-helpers"
  `(toplevel
     ,(make-safe-divider 'safe-ratio 1d-6)
     ,(make-safe-divider 'coarse-ratio 1d-3)))
```

This writes:
```lisp
(defun safe-ratio (numerator denominator)
  (cond
    ((< (abs denominator) 1.0d-6)
     ;; Avoid division by zero
     nil)
    (t (/ numerator denominator))))

(defun coarse-ratio (numerator denominator)
  (cond
    ((< (abs denominator) 0.001)
     ;; Avoid division by zero
     nil)
    (t (/ numerator denominator))))
```

### 3. Named/Keyword Arguments via List Destructuring
Inside generator helpers, you can use `destructuring-bind` with keyword parameters on a single flat list to simulate named parameters. This is highly readable and keeps code-building logic modular.

#### Example:
```lisp
(defun make-test-defun (args-list)
  (destructuring-bind (&key name params body) args-list
    `(defun ,name ,params
       ,@body)))

;; Usage in template:
`(toplevel
   ,(make-test-defun '(:name hello :params (x) :body ((print x) x))))
```

---

## Advanced Code Generation & Troubleshooting

### 1. Bypassing Pretty-Printer Dispatch Rules
The generator registers pprint dispatchers for common symbols like `do0` and `comments` which automatically format them (e.g. stripping outer parentheses, turning `(comments ...)` into raw `;;` blocks). If you want to print these symbols literally into your generated Lisp file, qualify them with the target package namespace (e.g., `target-pkg:do0` or `target-pkg:comments`). Since the dispatchers only match the exact package-local symbol of `cl-cl-generator`, the package-qualified target symbol will bypass the dispatcher and print literally, resolving to the correct local symbol once loaded under `in-package`.

### 2. Format Control Strings and Unary Tilde Escaping
When generating code that formats unary prefix operators (like `~`), be careful with Common Lisp `format` strings. In Lisp, `~~` prints as a literal tilde. If you dynamically generate format control strings for operators, ensure you escape any literal tilde (`~`) in operator strings to `~~`.

For example:
```lisp
;; If py-op is "~"
(let ((escaped-op (cl-ppcre:regex-replace-all "~" py-op "~~")))
  (format nil "~a~~a" escaped-op val))
```
Otherwise, the generated format string will have zero directives (e.g., `"~~a"`) but receive arguments, triggering compiler style warnings.

### 3. Preventing Reader Package Errors
When evaluating code generators that reference external symbols (e.g. `jonathan:to-json` or `cl-ppcre:regex-replace-all`), the Lisp reader requires those packages to exist at read-time, even if they are inside unevaluated backquoted templates.

Always ensure the generator script quickloads all dependencies of the target files inside an `eval-when` block:
```lisp
(eval-when (:compile-toplevel :execute :load-toplevel)
  (let ((current-dir (make-pathname :directory (pathname-directory *load-pathname*))))
    ;; Register local project directories in central registry
    (push (merge-pathnames "../../" current-dir) asdf:*central-registry*)
    (push (merge-pathnames "../../../cl-py-generator/" current-dir) asdf:*central-registry*))
  (ql:quickload '(:cl-cl-generator :cl-py-generator :jonathan :cl-ppcre)))
```

### 4. Nesting Templates via Raw String Escaping (`(raw "...")`)
When generating helper macros or utilities that themselves contain backquotes, commas, or other reader-splicing commands, the outer generator's S-expression reader will evaluate them prematurely. 
To bypass this, represent those code blocks as literal strings wrapped inside `(raw "...")` forms. This writes the macro definitions verbatim to the output file.

### 5. Special Variable Defaults in Lambda Lists
In transpiler templates, if a generated function defaults an argument to a special or global dynamic variable (e.g. `(gc *gc*)`), do **not** quote the variable. Default expressions in `defun` lambda lists are evaluated at runtime call-time rather than compile/load-time, avoiding symbol-to-value type errors during serialization.

