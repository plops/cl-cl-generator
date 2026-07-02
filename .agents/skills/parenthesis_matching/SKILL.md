---
name: parenthesis-matching
description: Techniques and tools for finding and fixing mismatched parenthesis, brackets, and brace errors in Lisp S-expression templates and files.
---

# Parenthesis and Brace Matching Debugging Guide

When working with nested S-expressions (like Common Lisp templates, macro generators, or splicing logic), finding mismatched parentheses, brackets, or braces is a common challenge. Standard compiler error messages (like "malformed let* binding" or "unmatched close parenthesis") often point to the end of the file or to unrelated forms far away from the actual mismatch.

This guide documents three highly effective techniques to quickly pinpoint and resolve parenthesis errors.

---

## 1. Python line-by-line parenthesis depth counter

A quick way to find mismatched parentheses is to run a script that counts open and close parentheses line-by-line and prints the cumulative depth. This will highlight exactly where the nesting level increases or decreases incorrectly.

### Script snippet:
```python
import re

with open("path/to/file.lisp", "r") as f:
    lines = f.readlines()

depth = 0
for idx, line in enumerate(lines):
    # Remove format strings, double-quoted strings, and comment lines
    clean_line = ""
    in_string = False
    i = 0
    while i < len(line):
        if line[i] == ";" and not in_string:
            break
        elif line[i] == '"' and (i == 0 or line[i-1] != '\\'):
            in_string = not in_string
        elif not in_string:
            clean_line += line[i]
        i += 1
    
    opens = clean_line.count('(')
    closes = clean_line.count(')')
    depth += opens - closes
    
    # Print lines that change the depth or contain parentheses
    if opens > 0 or closes > 0:
        print(f"{idx+1:3d} (Depth: {depth:2d}) | +{opens} -{closes} | {line.strip()}")
```

### How to use:
Look at the output and trace the cumulative depth column. If you see the depth drop unexpectedly or end at a non-zero value at the end of a top-level form or the file, the mismatched parenthesis is located right on or immediately before that line.

---

## 2. SBCL diagnostic reader loop

Common Lisp's reader (`read`) parses forms one by one. You can use SBCL to read the file programmatically and catch reader errors immediately. If the reader encounters an unmatched parenthesis or reaches the end of the file before a form is closed, it will throw a `simple-reader-error` indicating the exact line and column number of the offending character.

### Terminal command:
```bash
sbcl --eval '(with-open-file (s "path/to/file.lisp")
               (let ((*read-suppress* nil))
                 (handler-bind ((error (lambda (c)
                                         (format t "Reader Error: ~a~%" c)
                                         (sb-ext:exit :code 0))))
                   (loop for form = (read s nil :eof)
                         until (eq form :eof)
                         do (format t "Successfully read form starting with: ~a~%"
                                    (and (listp form) (car form)))))))' --eval '(quit)'
```

### Why it works:
Unlike loading or compiling (which fails with vague grammatical errors like "malformed binding"), this command reads each top-level form individually. It tells you:
1. Which top-level forms were successfully read.
2. The exact line and column where the reader encountered an unmatched close parenthesis or unclosed block.

---

## 3. Splicing parenthesis gotchas (`,@`)

When writing code generators using backquotes (\`) and splices (`,@`), it is common to write loops like:

```lisp
`(toplevel
   ,@(loop for (sym inst) in '\''((workdir "WORKDIR") (user "USER"))
           collect `(,sym (format nil "~a ~a" ,inst (emit-val (second code))))))
```

### The Pitfall:
At the end of the `collect` form, there are multiple closing parentheses. It is easy to write too many or too few.
Let's count the matching parentheses:
- `(second code)` - closed by `)` (1)
- `(emit-val ...)` - closed by `)` (2)
- `(format ...)` - closed by `)` (3)
- `(,sym ...)` backquote - closed by `)` (4)
- `(loop ...)` - closed by `)` (5)

So exactly **5** close parentheses are needed at the end of that line: `code)))))`.
If you write 6, you will close the outer `toplevel` form early, which causes the subsequent forms in the generator to be parsed as top-level forms or malformed bindings instead of being part of the template.
Always use the depth counter or SBCL reader diagnostic to verify the depth of splicing lines.
