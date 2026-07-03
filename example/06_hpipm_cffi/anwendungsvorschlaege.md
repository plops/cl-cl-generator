# cl-cl-generator – Anwendungsvorschläge

Das System ist ein **homoikonischer Metaprogrammierungs-Rahmen**: Lisp-Code erzeugt Lisp-Code,
wobei der Standard-Pretty-Printer für konsistente Formatierung sorgt und `sxhash`-Caching unnötige
Neukompilierungen verhindert. Die bestehenden Beispiele zeigen bereits fünf Einsatzfelder:

## Was bereits existiert

| Beispiel | Was es demonstriert |
|---|---|
| [00_test](file:///workspace/src/cl-cl-generator/example/00_test) | Grundlegende Funktionsdefinitionen, Kommentare, Git-Hash-Einbettung |
| [01_meta](file:///workspace/src/cl-cl-generator/example/01_meta) | **Bootstrapping** – der Generator erzeugt seinen eigenen Kern ([cl.lisp](file:///workspace/src/cl-cl-generator/cl.lisp)) |
| [03_py_meta](file:///workspace/src/cl-cl-generator/example/03_py_meta) | Generiert [py.lisp](file:///workspace/src/cl-cl-generator/example/03_py_meta/py.lisp) des `cl-py-generator` (~57 KB) aus ~47 KB Generator-Code |
| [04_tui_cockpit](file:///workspace/src/cl-cl-generator/example/04_tui_cockpit) | Generiert `/proc`-Parser und ein interaktives TUI-Dashboard (tuition) |
| [05_dockerfile_meta](file:///workspace/src/cl-cl-generator/example/05_dockerfile_meta) | Vollständige Dockerfile-DSL mit Heredoc, Multi-stage, Healthcheck |

---

## Neue Anwendungsvorschläge

### 1. 🔧 ASDF-System-Generator
**Idee**: Generiert `.asd`-Dateien aus einer deklarativen Beschreibung.

```lisp
`(defsystem ,name
   :depends-on ,@(loop for dep in deps collect `(:require ,dep))
   :components ,(make-component-tree source-files))
```

**Nutzen**: Große Projekte mit vielen Komponenten und bedingten Abhängigkeiten
(z. B. `#+sbcl`-Features) lassen sich loop-basiert ohne Copy-Paste pflegen.
Änderungen an der Struktur werden regeneriert, nicht manuell synchronisiert.

---

### 2. 🧪 Test-Boilerplate-Generator (FiveAM / Parachute)
**Idee**: Definiert Testsuiten aus einer Daten-getriebenen Tabelle.

```lisp
,@(loop for (fn input expected) in test-cases collect
    `(test ,(intern (format nil "TEST-~a-~a" fn input))
       (is (equal ,expected (,fn ,input)))))
```

**Nutzen**: Hunderte Regressionstests aus einer einzigen Liste von `(funktion eingabe erwartet)`-Tripeln.
Neue Testfälle werden durch Hinzufügen einer Zeile in der Datentabelle ergänzt, nicht durch
manuelles Kopieren von `deftest`-Blöcken.

---

### 3. 📐 FFI-Binding-Generator (CFFI)
**Idee**: Generiert `cffi:defcfun`, `defcstruct` und Wrapper-Funktionen aus einer
maschinenlesbaren C-Header-Beschreibung (z. B. einer simplen S-Expression-Spec).

```lisp
,@(loop for (c-name ret-type params) in c-api-spec collect
    `(cffi:defcfun (,c-name ,(lispify c-name)) ,ret-type
       ,@(loop for (pname ptype) in params collect
           `(,pname ,ptype))))
```

**Nutzen**: C-Bibliotheken mit vielen ähnlichen Funktionen (OpenGL, BLAS, Linux-Syscalls)
erzeugen massenweise repetitive CFFI-Bindings. Der Generator eliminiert diese Fleißarbeit
vollständig und erzeugt gleichzeitig Kommentare aus den Signaturen.

---

### 4. 🌐 HTTP-Handler-Scaffolding (Hunchentoot / Snooze)
**Idee**: Generiert Route-Handler und URL-Dispatcher aus einer REST-API-Spezifikation.

```lisp
,@(loop for route in api-routes collect
    `(hunchentoot:define-easy-handler
         (,(route-handler-name route) :uri ,(route-path route)
                                      :request-type ,(route-method route))
         ()
       (comment ,(format nil "Handler für ~a ~a" (route-method route) (route-path route)))
       (setf (hunchentoot:content-type*) "application/json")
       (jonathan:to-json ,(route-body route))))
```

**Nutzen**: OpenAPI/Swagger-Spec als S-Expression einlesen und vollständige
Handler-Skelette erzeugen – inklusive einheitlicher Fehlerbehandlung und Logging.

---

### 5. 🗄️ SQL-DDL-Generator / ORM-Layer
**Idee**: Generiert `defclass`-Definitionen mit Slots aus Datenbank-Schemata,
plus zugehörige `INSERT`/`SELECT`-Hilfsfunktionen.

```lisp
,@(loop for table in schema collect
    `(defclass ,(table-class table) ()
       ,(loop for col in (table-columns table) collect
          `(,(col-slot col)
            :accessor ,(col-accessor col)
            :initarg  ,(col-keyword col)
            :type     ,(sql-type->lisp (col-type col))
            :documentation ,(col-comment col)))))
```

**Nutzen**: Schema-Änderungen (neue Spalte, Typ-Änderung) werden in der
S-Expression-Spec vorgenommen und erzeugen neu generierten Code ohne manuelles
Anpassen von Dutzenden Slot-Definitionen.

---

### 6. ⚙️ Konfigurations-DSL (YAML/TOML-Ersatz)
**Idee**: Schreibt Anwendungskonfigurationen als S-Expressions, die zu einem
validierten, typgesicherten Lisp-Modul kompiliert werden.

```lisp
`(toplevel
   (comment "Generiert aus config.sexp – nicht manuell bearbeiten")
   (defparameter *db-host* ,db-host)
   (defparameter *db-port* ,db-port)
   ,@(loop for (key val) in feature-flags collect
       `(defparameter ,(intern (format nil "*FEATURE-~a*" key)) ,val)))
```

**Nutzen**: Konfiguration wird zur Ladezeit kompiliert, Typen werden vom Lisp-Compiler
geprüft, und REPL-basierte Inspektion funktioniert mit `describe`. Kein JSON/YAML-Parser nötig.

---

### 7. 📊 Daten-Driven Structs + Serializer
**Idee**: Generiert `defstruct` oder `defclass` plus passende JSON-/Binary-Serializer
aus einem kompakten Schema.

```lisp
,@(loop for field in (struct-fields spec) collect
    (list (field-name field)
          :type (field-type field)
          :initform (field-default field)))
```

Dazu zugehörige `to-json` / `from-bytes` Funktionen per Loop generieren –
konsistent und ohne Drift zwischen Struct-Definition und Serializer.

---

### 8. 🐧 Systemd-Unit-Generator
**Idee**: Analog zum Dockerfile-Generator eine DSL für `.service`-, `.timer`- und
`.socket`-Unit-Dateien schreiben.

```
[Unit]
Description=My Service
After=network.target

[Service]
ExecStart=/usr/bin/myapp
```

**Nutzen**: Mehrere ähnliche Dienste (z. B. 10 Worker-Instanzen mit
unterschiedlichen Ports) werden per Loop aus einer Parameterliste generiert,
statt 10 fast-identische `.service`-Dateien manuell zu pflegen.

---

### 9. 🔬 Mathematik / Numerik: Spezialisierte Varianten generieren
**Idee**: Generiert typspezialisierte Varianten einer numerischen Funktion
(single-float, double-float, complex) aus einer einzigen Definition.

```lisp
,@(loop for (suffix type) in '((f single-float) (d double-float) (c complex))
        collect
        `(defun ,(intern (format nil "INTEGRATE-~a" suffix))
             (f a b n)
           (declare (type ,type a b)
                    (function f))
           ...))
```

**Nutzen**: Typ-Deklarationen und Optimierungs-Hints werden konsistent über alle
Varianten hinweg generiert, ohne Gefahr von Copy-Paste-Fehlern bei
Performance-kritischem Code.

---

### 10. 🎨 Makro-Bibliothek aus Spezifikation
**Idee**: Nutzt den Generator als **Makro-Compiler zweiter Ordnung**: Beschreibt
eine Menge von Makros deklarativ als Transformationsregeln und generiert daraus
die `defmacro`-Definitionen.

```lisp
,@(loop for (name pattern expansion) in macro-rules collect
    `(defmacro ,name ,pattern
       (comment ,(format nil "Generiert aus Regel: ~a" name))
       ,expansion))
```

**Nutzen**: Eine Makro-Bibliothek für eine eingebettete DSL (z. B. für
Signalverarbeitung oder Robotik) wird deklarativ beschrieben und erzeugt
einheitlich dokumentierten, formatierten Code.

---

## Welche Stärken demonstrieren diese Vorschläge?

| Stärke | Demonstriert durch |
|---|---|
| **Homöikonizität** – Code = Daten | Alle Vorschläge; besonders #1, #10 |
| **Eliminate Boilerplate per Loop** | #2, #3, #7, #9 |
| **Cross-Domain Code Generation** | #8 (Systemd), #4 (HTTP), #5 (SQL) |
| **Typ-Sicherheit durch Lisp-Compiler** | #6, #9 |
| **Bootstrapping / Selbstreflexion** | #10; analog zu 01_meta |
| **mtime-Caching = inkrementelle Builds** | Alle (eingebaut durch `write-source`) |

> [!TIP]
> Die Anwendungen #3 (FFI-Bindings) und #9 (numerische Varianten) haben einen
> besonders starken "Wow-Faktor", weil sie zeigen, dass die Mächtigkeit des
> Systems **nicht von der Komplexität der DSL abhängt**, sondern vom
> Generierungszeit-Lisp selbst.
