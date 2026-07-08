# Implementation Plan - Korrektur des Tuition Cockpits

Dieser Plan beschreibt die notwendigen Korrekturen an `gen02.lisp`, den generierten Dateien in `source02/` und den begleitenden Planungsdokumenten.

## Ziel

Die aktuelle Version soll so angepasst werden, dass sie:
- die echte `tuition`-API korrekt verwendet,
- als ASDF-System sauber ladbar ist,
- die Throttling-Funktion nicht nur dekorativ, sondern tatsächlich initialisiert,
- und die Dokumentation nicht mehr widersprüchlich ist.

## Festgestellte Probleme

1. **Falscher System-/Paketbezug in der Dokumentation**
   - DeepWiki bestätigt: das ASDF-System heißt `tuition`.
   - Die Dokumente im `source02/plan/` verwenden teilweise noch falsche oder uneinheitliche Namen.

2. **Throttling-Setup ist unvollständig**
   - `setup-throttling-class` wird im aktuellen Ablauf nicht aufgerufen.
   - `throttle-pid` schreibt direkt nach `cgroup.procs`, ohne ein belastbares Vorbereitungs-Setup.

3. **README- und Verifikationspfade sind fehleranfällig**
   - Das Testkommando im README verwendet eine Shell-Substitution innerhalb eines Lisp-Strings.
   - Dadurch ist der Befehl nicht zuverlässig ausführbar.

4. **Plan-/Dateinamen sollten konsistent sein**
   - Die generierten Dateien heißen `cockpit-tui.asd`, `package.lisp`, `cockpit.lisp`, `tests.lisp`.
   - Die Planungsunterlagen sollten dieselben Bezeichnungen verwenden.

## Umsetzung

### 1. API und ASDF korrigieren
- `source02/cockpit-tui.asd` auf das echte `tuition`-System prüfen.
- In `package.lisp` sicherstellen, dass das Package `:tuition` nutzt und nicht eine eigene, abweichende API annimmt.
- Alle Verweise in den Planungsdateien auf die falsche Systembezeichnung gegen die korrekte Terminologie abgleichen.

### 2. Throttling stabilisieren
- `setup-throttling-class` in einen echten Initialisierungspfad integrieren.
- Fehlerfälle explizit in der Statuszeile sichtbar machen.
- Prüfen, ob `throttle-pid` bei fehlendem cgroup-Verzeichnis mit einer klaren Statusmeldung reagiert.

### 3. Dokumentation bereinigen
- `source02/plan/implementation_plan.md` und `source02/plan/walkthrough.md` auf korrekte Namen und Pfade aktualisieren.
- Das README so anpassen, dass die Beispielbefehle direkt ausführbar sind.

### 4. Generator und generierte Dateien abgleichen
- `gen02.lisp` als Quelle der Wahrheit prüfen.
- Generator und bereits erzeugte Dateien synchronisieren, damit die Ausgabe reproduzierbar bleibt.

## Verifikation

1. Generator ausführen und `source02/` neu erzeugen.
2. ASDF-System laden.
3. Testsystem ausführen.
4. Einmal manuell prüfen, ob der TUI-Startpfad und die Hilfe-/Quit-Tasten wie erwartet funktionieren.

## Abnahmekriterium

Die Korrektur ist abgeschlossen, wenn die Dokumentation konsistent ist, das System mit `tuition` ladbar ist und die genannte Initialisierung für Throttling nicht mehr nur auf dem Papier existiert.
