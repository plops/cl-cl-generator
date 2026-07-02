# cl-dockerfile-generator (Deutsch)

`cl-dockerfile-generator` ist eine Common Lisp DSL und ein Transpiler, mit dem Sie Dockerfiles mithilfe von S-Expressions dynamisch generieren können. Durch die Nutzung der Case-Inversion des Lisp-Readers und des Raw-String-Makros (`#r`) wird Boilerplate-Code vermieden, mehrzeiliges Skripting vereinfacht und eine saubere Formatierung garantiert.

---

### Schreibweise & Symbole
Der Generator läuft unter der `:invert` Readtable-Case.
- **Standard-Symbole**: Großgeschriebene Symbole werden in Großbuchstaben ausgegeben (z. B. `DEBIAN_FRONTEND` -> `DEBIAN_FRONTEND`), und kleingeschriebene Symbole werden in Kleinbuchstaben ausgegeben (z. B. `noninteractive` -> `noninteractive`).
- **Senkrechte Striche `|...|`**: Verhindern das Splitten von Symbolen mit Leerzeichen und Sonderzeichen. Z. B. wird `|apt-get update|` zu `apt-get update`. Wichtig: Großbuchstaben innerhalb der Striche verwenden, um Kleinbuchstaben in der Dockerfile zu erhalten (z. B. `|APT-GET UPDATE|` -> `apt-get update`).
- **Strings**: In Anführungszeichen gesetzte Strings (z. B. `"ubuntu:26.04"`) werden exakt wie geschrieben und ohne Invertierung ausgegeben.

---

### Syntax-Referenz im HyperSpec-Stil

#### 1. `toplevel`
**toplevel** `{`*instruction*`}`\*
- **Beschreibung**: Gruppiert mehrere Dockerfile-Anweisungen und schreibt sie nacheinander in jeweils neue Zeilen.
- **Beispiel**:
  ```lisp
  (toplevel
    (from "ubuntu:26.04")
    (run "apt-get update"))
  ```
- **Ausgabe**:
  ```dockerfile
  FROM ubuntu:26.04
  RUN apt-get update
  ```

#### 2. `directive`
**directive** *name* *value*
- **Beschreibung**: Erzeugt Parser-Direktiven (wie Syntax-Erweiterungen).
- **Beispiel**: `(directive syntax "docker/dockerfile:1")`
- **Ausgabe**: `# syntax=docker/dockerfile:1`

#### 3. `from`
**from** *image* `[&key` *as*`]`
- **Beschreibung**: Definiert das Basis-Image eines Build-Stages. Unterstützt das Keyword-Argument `:as` für mehrstufige Builds.
- **Beispiele**:
  - `(from "ubuntu:26.04")` -> `FROM ubuntu:26.04`
  - `(from "ubuntu:26.04" :as builder)` -> `FROM ubuntu:26.04 AS builder`

#### 4. `arg`
**arg** *name* `[`*value*`]`
- **Beschreibung**: Definiert eine Build-Variable mit optionalem Standardwert.
- **Beispiele**:
  - `(arg VERSION)` -> `ARG VERSION`
  - `(arg DEBIAN_FRONTEND noninteractive)` -> `ARG DEBIAN_FRONTEND=noninteractive`

#### 5. `env`
**env** `{`*key* *value*`}`\*
- **Beschreibung**: Definiert Umgebungsvariablen. Mehrere Zuweisungen werden über mehrere Zeilen mit Backslash-Umbruch formatiert.
- **Beispiele**:
  - `(env MY_VAR 123)` -> `ENV MY_VAR=123`
  - `(env VAR1 val1 VAR2 val2)`
    - **Ausgabe**:
      ```dockerfile
      ENV VAR1=val1 \
          VAR2=val2
      ```

#### 6. `run`
**run** `[&key` *mount* *heredoc*`]` *command*
- **Beschreibung**: Führt Befehle in einem neuen Shell-Layer aus. Unterstützt das optionale Keyword `:mount` für Build-Mounts und `:heredoc` für mehrzeilige Skripte.
- **Beispiele**:
  - `(run "apt-get update")` -> `RUN apt-get update`
  - `(run :mount "type=cache,target=/root/.cache/uv" "uv pip install google-antigravity")`
    - **Ausgabe**: `RUN --mount=type=cache,target=/root/.cache/uv uv pip install google-antigravity`
  - `(run :heredoc "echo 'hello'\necho 'world'")`
    - **Ausgabe**:
      ```dockerfile
      RUN <<EOF
      echo 'hello'
      echo 'world'
      EOF
      ```

#### 7. `and` / `seq` / `pipe`
**and** `{`*command*`}`\*  
**seq** `{`*command*`}`\*  
**pipe** `{`*command*`}`\*
- **Beschreibung**: Verkettungs-Operatoren für Shell-Befehle.
  - **`and`** verkettet Befehle mit `&&` und Zeilenumbruch.
  - **`seq`** verkettet Befehle mit `;` und Zeilenumbruch.
  - **`pipe`** leitet Ausgaben per `|` weiter.
- **Beispiele**:
  - `(run (and "apt-get update" "apt-get install -y curl"))`
    - **Ausgabe**:
      ```dockerfile
      RUN apt-get update \
       && apt-get install -y curl
      ```
  - `(run (seq "cd /tmp" "tar -xf src.tar.gz"))`
    - **Ausgabe**:
      ```dockerfile
      RUN cd /tmp \
      ; tar -xf src.tar.gz
      ```
  - `(run (pipe "cat a.txt" "grep -i hello"))`
    - **Ausgabe**: `RUN cat a.txt | grep -i hello`

#### 8. `copy`
**copy** `[&key` *from* *chown*`]` `{`*source*`}`\* *destination*  
**copy** `:heredoc` *destination* *content*
- **Beschreibung**: Kopiert Dateien, Ordner oder schreibt Heredoc-Inhalte direkt in Dateien. Unterstützt die Keyword-Argumente `:from` und `:chown`.
- **Beispiele**:
  - `(copy "src" "dest")` -> `COPY src dest`
  - `(copy "src" "dest" :from builder :chown "root:root")` -> `COPY --from=builder --chown=root:root src dest`
  - `(copy :heredoc "dest" "hello world")`
    - **Ausgabe**:
      ```dockerfile
      COPY <<EOF dest
      hello world
      EOF
      ```

#### 9. `add`
**add** `[&key` *chown*`]` `{`*source*`}`\* *destination*
- **Beschreibung**: Fügt Dateien, Verzeichnisse oder URLs von Remote-Ressourcen hinzu. Unterstützt optionales `:chown`.
- **Beispiel**:
  - `(add "http://example.com/file.tar.gz" "/dest")` -> `ADD http://example.com/file.tar.gz /dest`

#### 10. `expose`
**expose** `{`*port*`}`\*
- **Beschreibung**: Gibt Netzwerkports des Containers frei.
- **Beispiel**: `(expose 80 443)` -> `EXPOSE 80 443`

#### 11. `label`
**label** `{`*key* *value*`}`\*
- **Beschreibung**: Fügt Metadaten-Labels zum Image hinzu.
- **Beispiel**: `(label maintainer "alice" version "1.0")`
- **Ausgabe**:
  ```dockerfile
  LABEL maintainer="alice" \
        version="1.0"
  ```

#### 12. `onbuild`
**onbuild** *instruction*
- **Beschreibung**: Registriert Trigger, die ausgeführt werden, sobald dieses Image als Basis-Image dient.
- **Beispiel**: `(onbuild (run "echo 'triggered'"))` -> `ONBUILD RUN echo 'triggered'`

#### 13. `comment`
**comment** *string*
- **Beschreibung**: Fügt einen Kommentar ein, der mit `#` beginnt.
- **Beispiel**: `(comment "Dies ist ein Kommentar")` -> `# Dies ist ein Kommentar`

#### 14. `shell`
**shell** `(` `{`*arg*`}`\* `)`
- **Beschreibung**: Überschreibt die Standard-Shell zur Ausführung von Befehlen.
- **Beispiel**: `(shell ("/bin/bash" "-c"))` -> `SHELL ["/bin/bash", "-c"]`

#### 15. `stopsignal`
**stopsignal** *signal*
- **Beschreibung**: Setzt das Signal zum Beenden des Containers.
- **Beispiel**: `(stopsignal SIGTERM)` -> `STOPSIGNAL SIGTERM`

#### 16. `cmd` / `entrypoint` / `volume`
**cmd** *value*  
**entrypoint** *value*  
**volume** *value*
- **Beschreibung**: Definiert Laufzeiteigenschaften. *value* kann ein String/Symbol (Shell-Form) oder eine Liste von Strings/Symbols (Exec-Form) sein.
- **Beispiele**:
  - `(cmd ("echo" "hello"))` -> `CMD ["echo", "hello"]`
  - `(cmd "echo hello")` -> `CMD echo hello`
  - `(entrypoint ("/bin/bash" "-c"))` -> `ENTRYPOINT ["/bin/bash", "-c"]`
  - `(volume ("/data"))` -> `VOLUME ["/data"]`

#### 17. `healthcheck`
**healthcheck** *command* `[&key` *interval* *timeout* *start-period* *retries*`]`  
**healthcheck** `NONE`
- **Beschreibung**: Konfiguriert Integritätsprüfungen. Optionen: `:interval`, `:timeout`, `:start-period`, `:retries`.
- **Beispiele**:
  - `(healthcheck (cmd ("curl" "-f" "http://localhost/")) :interval "5s" :timeout "3s" :retries 3)`
    - **Ausgabe**: `HEALTHCHECK --interval=5s --timeout=3s --retries=3 CMD ["curl", "-f", "http://localhost/"]`
  - `(healthcheck NONE :start-period "10s")` -> `HEALTHCHECK --start-period=10s NONE`

#### 18. `#r` (Raw-Strings)
**#r** *bracket-delimited-form*  
**#r** *custom-delimiter* *content* *custom-delimiter*
- **Beschreibung**: Liest Zeichenketten oder Skripte case-sensitive und ohne Escaping ein.
- **Beispiele**:
  - `#r(echo "hello (world)")` -> `echo "hello (world)"`
  - `#r#echo "custom delimiter"#` -> `echo "custom delimiter"`
