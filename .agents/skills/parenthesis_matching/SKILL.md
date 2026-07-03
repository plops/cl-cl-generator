---
name: parenthesis-matching
description: Techniques and tools for finding and fixing mismatched parenthesis, brackets, and brace errors in Lisp S-expression templates and files.
---

# Parenthesis and Brace Matching Debugging Guide

When working with nested S-expressions (like Common Lisp templates, macro generators, or splicing logic), finding mismatched parentheses, brackets, or braces is a common challenge. Standard compiler error messages (like "malformed let* binding" or "unmatched close parenthesis") often point to the end of the file or to unrelated forms far away from the actual mismatch.

This guide documents three highly effective techniques to quickly pinpoint and resolve parenthesis errors.

---

## 1. Python full-file Lisp parenthesis parser

A quick way to find mismatched parentheses is to run a script that parses the file character-by-character, keeping track of multi-line strings, escaped characters, and comments, and printing the line-by-line depth of each top-level form.

### Script snippet:
```python
def parse_lisp_depth(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    in_string = False
    in_comment = False
    escaped = False
    depth = 0
    line_num = 1
    col_num = 1
    top_level_start = None
    
    i = 0
    while i < len(content):
        char = content[i]
        if char == '\n':
            line_num += 1
            col_num = 1
        else:
            col_num += 1
            
        if escaped:
            escaped = False
            i += 1
            continue
        if char == '\\':
            escaped = True
            i += 1
            continue
        if in_string:
            if char == '"':
                in_string = False
            i += 1
            continue
        if in_comment:
            if char == '\n':
                in_comment = False
            i += 1
            continue
        if char == ';':
            in_comment = True
            i += 1
            continue
        if char == '"':
            in_string = True
            i += 1
            continue
            
        if char == '(':
            if depth == 0:
                top_level_start = (line_num, col_num)
            depth += 1
        elif char == ')':
            depth -= 1
            if depth < 0:
                print(f"Error: unmatched close parenthesis at line {line_num}, col {col_num}")
                depth = 0
            elif depth == 0:
                print(f"Successfully closed top-level form starting at {top_level_start} (ended at line {line_num}, col {col_num})")
        i += 1
        
    if depth > 0:
        print(f"Error: EOF reached with depth {depth}. Unclosed form starts at {top_level_start}")

parse_lisp_depth("path/to/file.lisp")
```

### How to use:
Look at the output. If a form fails to close or has unmatched parentheses, the parser will print an error message indicating the exact line and column numbers.

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
