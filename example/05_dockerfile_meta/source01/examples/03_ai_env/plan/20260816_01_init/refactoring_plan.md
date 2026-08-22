# Refactoring-Plan für `gen_ai_env.lisp`

Dieser Plan beschreibt konkrete Schritte, um den Lisp-Code sauberer und wartbarer zu machen und gleichzeitig die Generierung der Docker-Builds (bzgl. Caching und Parallelität) zu optimieren.

## 1. Lisp-Code Refactoring (Reduzierung von Repetitionen)

Das aktuelle Skript enthält viel wiederkehrenden Code, der durch Lisp-spezifische Konstrukte (wie in den `cl-cl-generator` Skills beschrieben) vereinfacht werden kann.

### A. Smoke-Tests dynamisch generieren
Aktuell gibt es für jedes Tool eine eigene Funktion (`smoke-codex-test`, `smoke-kiro-cli-test`, `smoke-gcc-test`, etc.), die fast identisch aufgebaut ist.
**Lösung:** Wir definieren eine Hilfsfunktion `make-smoke-test` und iterieren über eine Liste von Definitionen mittels `,@(loop ...)`.
```lisp
(defun make-smoke-test (name description script)
  `((comment ,(format nil "Smoke test ~a" description))
    (run :heredoc ,script)))

;; Anwendung im Code:
`(,@(loop for (condition name desc script) in *smoke-tests*
          when (symbol-value condition)
          collect (make-smoke-test name desc script)))
```

### B. Wrapper-Skripte verallgemeinern
Die Funktionen `agent-wrapper-script`, `kiro-wrapper-script` und `grok-wrapper-script` enthalten hartgecodetes Shell-Skripting mit leichten Variationen.
**Lösung:** Eine generische Funktion `make-wrapper` könnte die Gemeinsamkeiten abstrahieren (z.B. Shebang, Setzen von `pipefail`, Argument-Übergabe).

### C. Deklaratives Abhängigkeits-Management für APT-Pakete
In `runner-stage` werden die APT-Pakete über viele `(when *install-...* (setf apt-packages (append ...)))` Blöcke zusammengebaut.
**Lösung:** Eine assoziative Liste (Alist), die Feature-Flags direkt auf die benötigten Pakete mappt. Das macht den Code kompakter und leichter erweiterbar.

---

## 2. Docker Build Optimierungen (Parallelität & Caching)

Die Struktur der generierten Dockerfile kann optimiert werden, um BuildKit besser auszunutzen.

### A. Parallelisierung durch Aufteilung der Builder-Stages
Momentan lädt die `builder-cli-stage` alle aktivierten CLI-Tools sequenziell herunter (Antigravity, Copilot, Kiro, TeamCity). 
**Lösung:** Da Docker BuildKit unabhängige Stages parallel ausführt, sollten wir für jedes CLI-Tool eine eigene kleine Builder-Stage definieren. 
*Beispiel:* `builder-agy`, `builder-copilot`, `builder-kiro`. 
In der abschließenden `runner-stage` werden dann die Binaries aus den jeweiligen separaten Stages mittels `COPY --from=...` eingesammelt. Das beschleunigt den Build massiv, da alle Downloads gleichzeitig laufen.

### B. Optimiertes Layer-Caching für APT
Aktuell gibt es in der `runner-stage` einen riesigen `apt-get install` Block. Wenn sich nur ein Feature-Flag ändert (z.B. `*install-gcc*` wird aktiviert), muss der gesamte APT-Block inklusive der 30+ Basis-Pakete neu installiert werden.
**Lösung:** 
1. **Basis-Installation:** Zuerst `apt-get install` nur für die statischen `*ubuntu-packages*` und universellen Tools.
2. **Modulspezifische Installationen:** Die modulspezifischen Pakete (z.B. GCC, Python, Emacs) erhalten jeweils eigene `RUN --mount=type=cache,target=/var/cache/apt apt-get install ...` Befehle. 
Dadurch bleiben vorherige Layer gecached, wenn eine neue Komponente hinzugeschaltet wird.

### C. Download-Caching
Für direkte `curl`-Downloads (wie Quicklisp oder Skripte) können wir zusätzlich `--mount=type=cache,target=/var/cache/downloads` nutzen, damit bei einem Fehler im Build-Prozess große Dateien nicht neu geladen werden müssen.

---

## Nächste Schritte

Wenn du mit diesen Vorschlägen einverstanden bist, klicke auf **Proceed** (oder antworte entsprechend), und ich werde die Änderungen in `gen_ai_env.lisp` implementieren. Wir können auch einzelne Punkte auswählen oder anpassen.
