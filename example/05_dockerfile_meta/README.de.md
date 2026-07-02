# cl-dockerfile-generator (Deutsch)

`cl-dockerfile-generator` ist eine Common Lisp DSL und ein Transpiler, mit dem Sie Dockerfiles mithilfe von S-Expressions dynamisch generieren können. Durch die Nutzung der Case-Inversion des Lisp-Readers und des Raw-String-Makros (`#r`) wird Boilerplate-Code vermieden, mehrzeiliges Skripting vereinfacht und eine saubere Formatierung garantiert.

---

### Schreibweise & Symbole
Der Generator läuft unter der `:invert` Readtable-Case.
- **Standard-Symbole**: Großgeschriebene Symbole werden in Großbuchstaben ausgegeben (z. B. `DEBIAN_FRONTEND` -> `DEBIAN_FRONTEND`), und kleingeschriebene Symbole werden in Kleinbuchstaben ausgegeben (z. B. `noninteractive` -> `noninteractive`).
- **Senkrechte Striche `|...|`**: Verhindern das Splitten von Symbolen mit Leerzeichen und Sonderzeichen. Z. B. wird `|apt-get update|` zu `apt-get update`. Wichtig: Großbuchstaben innerhalb der Striche verwenden, um Kleinbuchstaben in der Dockerfile zu erhalten (z. B. `|APT-GET UPDATE|` -> `apt-get update`).
- **Strings**: In Anführungszeichen gesetzte Strings (z. B. `"ubuntu:26.04"`) werden exakt wie geschrieben und ohne Invertierung ausgegeben.

---

### Syntax-Referenz im HyperSpec-Stil & Docker-Handbuch

#### 1. `toplevel`
**toplevel** `{`*instruction*`}`\*
- **DSL-Beschreibung**: Gruppiert mehrere Dockerfile-Anweisungen und schreibt sie nacheinander in jeweils neue Zeilen.
- **Docker-Kontext**: Ein generator-spezifisches Hilfskonstrukt. Es hat keine direkte Entsprechung in Docker, dient aber dazu, mehrere Anweisungen auf oberster Ebene nacheinander zu formatieren.
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
- **DSL-Beschreibung**: Erzeugt Parser-Direktiven.
- **Docker-Kontext**: Spezielle Kommentare ganz oben im Dockerfile, die das Verhalten des Builders konfigurieren (z. B. Aktivierung von BuildKit-Features wie Build-Mounts).
- **Beispiel**: `(directive syntax "docker/dockerfile:1")`
- **Ausgabe**: `# syntax=docker/dockerfile:1`

#### 3. `from`
**from** *image* `[&key` *as*`]`
- **DSL-Beschreibung**: Definiert das Basis-Image.
- **Docker-Kontext**: Bestimmt das Ausgangs-Image für alle nachfolgenden Befehle. Jedes Dockerfile muss mit `FROM` beginnen. In mehrstufigen Builds (Multi-stage builds) benennt der optionale Parameter `:as` die jeweilige Phase (z. B. `builder` oder `runner`), um später Dateien daraus kopieren zu können.
- **Beispiele**:
  - `(from "ubuntu:26.04")` -> `FROM ubuntu:26.04`
  - `(from "ubuntu:26.04" :as builder)` -> `FROM ubuntu:26.04 AS builder`

#### 4. `arg`
**arg** *name* `[`*value*`]`
- **DSL-Beschreibung**: Definiert eine Build-Variable.
- **Docker-Kontext**: Deklariert eine Variable, die Benutzer beim Erstellen des Images via `docker build --build-arg name=value` übergeben können. Diese Variablen existieren nur während des Build-Prozesses und sind im fertigen Container nicht mehr verfügbar.
- **Beispiele**:
  - `(arg VERSION)` -> `ARG VERSION`
  - `(arg DEBIAN_FRONTEND noninteractive)` -> `ARG DEBIAN_FRONTEND=noninteractive`

#### 5. `env`
**env** `{`*key* *value*`}`\*
- **DSL-Beschreibung**: Definiert Umgebungsvariablen.
- **Docker-Kontext**: Definiert dauerhafte Umgebungsvariablen im Container. Diese stehen sowohl beim Build als auch zur Laufzeit im ausgeführten Container bereit. Mehrere Variablen werden automatisch über mehrere Zeilen mit Backslash-Zeilenumbrüchen formatiert, um Image-Layer einzusparen.
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
- **DSL-Beschreibung**: Führt Befehle aus.
- **Docker-Kontext**: Führt Shell-Befehle aus (z. B. Installation von Paketen, Kompilierung), wodurch ein neuer Layer im Image entsteht.
  - `:mount` erlaubt es, Verzeichnisse (wie Caches des Paketmanagers) während des Builds einzubinden, um wiederholte Downloads zu vermeiden, ohne diese im fertigen Image zu speichern (z. B. `RUN --mount=type=cache,...`).
  - `:heredoc` erlaubt das direkte Hinzufügen mehrzeiliger Skripte im Dockerfile, wodurch unübersichtliche Ketten aus `&&` vermieden werden.
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
- **DSL-Beschreibung**: Logische Verkettungs-Operatoren.
- **Docker-Kontext**: Hilfsstrukturen zum Verketten von Shell-Befehlen in einem `RUN`-Layer:
  - **`and`** verbindet Befehle mit `&&` (bricht ab, falls ein Befehl fehlschlägt, was die Layer-Erstellung absichert).
  - **`seq`** verbindet Befehle mit `;` (führt alle nacheinander aus).
  - **`pipe`** verbindet Befehle mit `|` (leitet stdout des ersten in stdin des zweiten um).
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
- **DSL-Beschreibung**: Kopiert Dateien oder schreibt Heredoc-Inhalte.
- **Docker-Kontext**: Kopiert Dateien und Ordner vom Host-Rechner (Build-Kontext) in das Container-Image.
  - `:from` kopiert Dateien aus einer früheren Phase eines Multi-stage Builds (essenziell, um das finale Image klein zu halten).
  - `:chown` ändert direkt beim Kopieren die Dateirechte, was Image-Größe einspart (verhindert zusätzliche `RUN chown`-Befehle).
  - `:heredoc` schreibt den übergebenen Text direkt in eine neue Datei im Container.
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
- **DSL-Beschreibung**: Fügt Dateien oder Remote-URLs hinzu.
- **Docker-Kontext**: Ähnlich wie `copy`, hat jedoch erweiterte Fähigkeiten: Es kann Dateien von URLs herunterladen und lokale tar/zip-Archive automatisch beim Kopiervorgang entpacken.
- **Beispiel**:
  - `(add "http://example.com/file.tar.gz" "/dest")` -> `ADD http://example.com/file.tar.gz /dest`

#### 10. `expose`
**expose** `{`*port*`}`\*
- **DSL-Beschreibung**: Deklariert Container-Ports.
- **Docker-Kontext**: Dokumentiert, auf welchen Netzwerkports der Container zur Laufzeit lauscht. Dies veröffentlicht die Ports nicht tatsächlich, sondern dient als Metadaten-Vertrag für Orchestratoren und Portweiterleitungen.
- **Beispiel**: `(expose 80 443)` -> `EXPOSE 80 443`

#### 11. `label`
**label** `{`*key* *value*`}`\*
- **DSL-Beschreibung**: Fügt Metadaten-Schlüssel-Wert-Paare hinzu.
- **Docker-Kontext**: Fügt beschreibende Metadaten-Labels (z. B. Maintainer, Version, Beschreibung) zum Image hinzu.
- **Beispiel**: `(label maintainer "alice" version "1.0")`
- **Ausgabe**:
  ```dockerfile
  LABEL maintainer="alice" \
        version="1.0"
  ```

#### 12. `onbuild`
**onbuild** *instruction*
- **DSL-Beschreibung**: Registriert einen On-Build-Trigger.
- **Docker-Kontext**: Registriert eine Anweisung, die erst ausgeführt wird, wenn dieses fertige Image als Basis-Image für ein anderes Image verwendet wird (also in einem anderen Dockerfile via `FROM dieses-image`).
- **Beispiel**: `(onbuild (run "echo 'triggered'"))` -> `ONBUILD RUN echo 'triggered'`

#### 13. `comment`
**comment** *string*
- **DSL-Beschreibung**: Schreibt Kommentare.
- **Docker-Kontext**: Formatiert Kommentare beginnend mit `#` für menschliche Dokumentation.
- **Beispiel**: `(comment "Dies ist ein Kommentar")` -> `# Dies ist ein Kommentar`

#### 14. `shell`
**shell** `('(` `{`*arg*`}`\* `))`
- **DSL-Beschreibung**: Konfiguriert die Standard-Shell.
- **Docker-Kontext**: Überschreibt die standardmäßig verwendete Shell zur Ausführung nachfolgender `RUN`-, `CMD`- und `ENTRYPOINT`-Anweisungen (z. B. Wechsel von `/bin/sh -c` auf `["/bin/bash", "-c"]`).
- **Beispiel**: `(shell ("/bin/bash" "-c"))` -> `SHELL ["/bin/bash", "-c"]`

#### 15. `stopsignal`
**stopsignal** *signal*
- **DSL-Beschreibung**: Setzt das Container-Stoppsignal.
- **Docker-Kontext**: Bestimmt das Signal des Systemaufrufs, das an den Container-Prozess gesendet wird, um ihn zu beenden (z. B. `SIGTERM` oder `SIGKILL`).
- **Beispiel**: `(stopsignal SIGTERM)` -> `STOPSIGNAL SIGTERM`

#### 16. `cmd`
**cmd** *value*
- **DSL-Beschreibung**: Setzt Standard-Argumente oder -Befehle.
- **Docker-Kontext**: Definiert den Standardbefehl, der beim Starten des Containers ausgeführt wird. Wenn der Benutzer den Container mit eigenen Argumenten startet (z. B. `docker run mein-image custom-command`), wird der `cmd`-Wert komplett überschrieben.
  - Wenn *value* eine **Liste von Strings** ist, läuft es in der *Exec-Form* (führt die Binärdatei direkt und ohne Shell-Wrapper aus: `["echo", "hello"]`).
  - Wenn *value* ein **einzelner String oder Symbol** ist, läuft es in der *Shell-Form* (wird als Unterbefehl von `/bin/sh -c` ausgeführt: `"echo hello"`).
- **Beispiele**:
  - `(cmd ("echo" "hello"))` -> `CMD ["echo", "hello"]`
  - `(cmd "echo hello")` -> `CMD echo hello`

#### 17. `entrypoint`
**entrypoint** *value*
- **DSL-Beschreibung**: Setzt den ausführbaren Einstiegspunkt.
- **Docker-Kontext**: Konfiguriert den Container so, dass er wie eine ausführbare Datei (CLI) läuft. Im Gegensatz zu `cmd` wird `entrypoint` *nicht* überschrieben, wenn Argumente beim Container-Start übergeben werden; diese werden stattdessen an den Entrypoint-Befehl angehängt. Wird oft in Kombination mit `cmd` verwendet (das dann optionale Standardargumente liefert).
- **Beispiele**:
  - `(entrypoint ("/bin/bash" "-c"))` -> `ENTRYPOINT ["/bin/bash", "-c"]`
  - `(entrypoint "/bin/bash")` -> `ENTRYPOINT /bin/bash`

#### 18. `volume`
**volume** *value*
- **DSL-Beschreibung**: Erstellt einen Mountpoint für Daten.
- **Docker-Kontext**: Deklariert ein Verzeichnis innerhalb des Containers als externen Einhängepunkt. Dies signalisiert Docker, dass dieses Verzeichnis Daten (wie Datenbanken oder Logs) außerhalb des Container-Lebenszyklus auf dem Host oder in Docker-Volumes speichern soll, wodurch das Copy-on-Write-Dateisystem des Containers umgangen wird.
- **Beispiele**:
  - `(volume ("/data"))` -> `VOLUME ["/data"]`
  - `(volume "/data")` -> `VOLUME /data`

#### 19. `healthcheck`
**healthcheck** *command* `[&key` *interval* *timeout* *start-period* *retries*`]`  
**healthcheck** `NONE`
- **DSL-Beschreibung**: Konfiguriert Integritätsprüfungen.
- **Docker-Kontext**: Konfiguriert einen Befehl, um regelmäßig zu prüfen, ob der Container noch ordnungsgemäß läuft (z. B. Testen, ob ein Webserver reagiert).
  - `:interval` bestimmt, wie oft der Test läuft.
  - `:timeout` bestimmt die maximale Laufzeit für einen Test.
  - `:start-period` ist eine Anlauf-Schonfrist, bevor Tests beginnen (gibt dem Container Zeit zum Booten).
  - `:retries` ist die Anzahl aufeinanderfolgender Fehler, bis der Container als defekt (`unhealthy`) markiert wird.
  - `NONE` deaktiviert alle Integritätsprüfungen des Eltern-Images.
- **Beispiele**:
  - `(healthcheck (cmd ("curl" "-f" "http://localhost/")) :interval "5s" :timeout "3s" :retries 3)`
    - **Ausgabe**: `HEALTHCHECK --interval=5s --timeout=3s --retries=3 CMD ["curl", "-f", "http://localhost/"]`
  - `(healthcheck NONE :start-period "10s")` -> `HEALTHCHECK --start-period=10s NONE`

#### 20. `#r` (Raw-Strings)
**#r** *bracket-delimited-form*  
**#r** *custom-delimiter* *content* *custom-delimiter*
- **DSL-Beschreibung**: Liest Zeichenketten ohne Lisp-spezifisches Maskieren ein.
- **Docker-Kontext**: Ein Reader-Makro, das es extrem einfach macht, rohen Text (wie reguläre Ausdrücke, sed-Skripte oder mehrzeiligen Code) an `run` oder `copy` zu übergeben, ohne Backslashes oder Anführungszeichen maskieren zu müssen.
- **Beispiele**:
  - `#r(echo "hello (world)")` -> `echo "hello (world)"`
  - `#r#echo "custom delimiter"#` -> `echo "custom delimiter"`
