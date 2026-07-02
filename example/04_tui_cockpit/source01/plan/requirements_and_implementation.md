# TUI Cockpit für Linux: Anforderungen & Implementierungsplan

Dieses Verzeichnis dokumentiert die Architektur und Designentscheidungen für ein ressourcen- und bandbreiteneffizientes Terminal-Cockpit (TUI) in Common Lisp, das mittels `cl-cl-generator` generiert wird.

---

## 1. Anforderungen (Requirements)

### 1.1. Bandbreitensparendes TUI-Design (SSH-freundlich bei 6 kB/s)
* **Ziel:** Die Benutzeroberfläche darf selbst bei sehr langsamen Verbindungen (z. B. 6 kB/s) die Leitung nicht verstopfen.
* **Maßnahmen zur Reduktion der Datenrate:**
  * **Double Buffering (Delta-Updates):** Es wird ein virtueller Bildschirm-Puffer im RAM gehalten. Beim Zeichnen vergleicht das System den neuen Zustand mit dem alten und sendet ausschließlich geänderte Zeichen an das Terminal (unter Verwendung gezielter ANSI-Escapes `ESC [ <y>;<x>H` zur Cursorpositionierung).
  * **Unterdrückung kosmetischer Redraws:** Kein ständiges Löschen des Bildschirms (`ESC [ 2J`), da dies das Terminal zwingt, jedes Zeichen neu zu übertragen.
  * **Konfigurierbare Refresh-Rate:** Standardmäßig ein langsames Intervall (z. B. alle 3 oder 5 Sekunden) oder rein manuelles Triggern per Tastendruck (z. B. `Leertaste`).
  * **Kompaktes ASCII-Layout:** Keine dekorativen Zeichenketten oder unnötigen Rahmen. Fokus auf Rohdaten und platzsparende Visualisierung.

### 1.2. Netzwerk-Bandbreitenüberwachung pro Prozess (Root erforderlich)
* **Ziel:** Identifikation von Prozessen, die unerwartet Bandbreite verbrauchen.
* **Technischer Ansatz (ohne eBPF/externe Tools):**
  1. Periodisches Auslesen von `/proc/net/tcp` (sowie `udp`, `tcp6`, `udp6`) zur Gewinnung der lokalen/entfernten IP-Ports und Socket-Inodes.
  2. Scannen aller Verzeichnisse `/proc/<pid>/fd/` zur Auflösung der Symlinks (z. B. `socket:[12345]`), um Socket-Inodes den jeweiligen PIDs zuzuordnen.
  3. Berechnung der Differenz der gesendeten/empfangenen Bytes über die Zeit, um die aktuelle Datenrate (Upload/Download) pro Prozess zu ermitteln.
* **Sicherheitsstufe:** Da `/proc/<pid>/fd/` für fremde Prozesse eingeschränkt ist, erfordert dieser Scan Root-Rechte.

### 1.3. Prozess-Drosselung (Bandbreitenbegrenzung)
* **Ziel:** Einem bandbreitenhungrigen Prozess zur Laufzeit eine Obergrenze zuweisen.
* **Technischer Ansatz (cgroups v2 & tc):**
  * **Keine externen Drosselungstools** (wie `trickle` oder `nethogs`).
  * Verwendung von **Linux cgroups v2**: Erstellung einer Untergruppe unter `/sys/fs/cgroup/` (z. B. `/sys/fs/cgroup/tui-throttle/`).
  * Zuweisung des Netzwerk-Traffics über **Linux Traffic Control (`tc`)**: Einrichten einer `clsact` Qdisc und Filterregeln, die Traffic aus der cgroup auf eine bestimmte Bandbreite drosseln.
  * Dynamisches Hinzufügen von Prozessen durch Schreiben der PID in die Datei `cgroup.procs` der jeweiligen Gruppe.

### 1.4. VPS & VM-Nachbar-Monitoring (Ressourcen-Steal)
* **CPU Steal Time:** Auslesen von `/proc/stat` (8. Spalte der `cpu`-Zeile). Berechnet den Prozentsatz der CPU-Zyklen, die uns der Hypervisor vorenthält, weil andere VMs auf dem Host aktiv sind.
* **I/O Pressure (PSI):** Auslesen von `/proc/pressure/io`, um festzustellen, wie stark das System durch I/O-Wartezeiten blockiert ist (oft ein Indikator für überlastete Host-Festplatten).
* **OOM Score:** Auslesen von `/proc/<pid>/oom_score`, um Speicherengpässe und die Abschuss-Priorität des Kernels zu überwachen.
* **Swap-Aktivität:** Auslesen von `/proc/vmstat` (Vergleich von `pswpin` und `pswpout`), um aktives Paging zu erkennen.

---

## 2. Implementierungsdetails & Architektur

### 2.1. Code-Generierung mit `cl-cl-generator`
Um Boilerplate und Code-Duplikate zu minimieren, wird der Lisp-Quellcode für das Cockpit generiert.
* **Vorteile der Metaprogrammierung in `gen.lisp`:**
  * **Parser-Schablonen:** Die verschiedenen `/proc`-Parser (wie `/proc/stat`, `/proc/pressure/io`, `/proc/vmstat`) teilen sich strukturelle Ähnlichkeiten (Dateien zeilenweise lesen, splitten, bestimmte Spalten extrahieren). Diese Parser werden über Makros/Schleifen zur Generierungszeit erzeugt.
  * **Historien-Buffer:** Datenstrukturen zur Speicherung historischer Verläufe (z. B. Ringpuffer für CPU-Steal und Bandbreite) werden über Lisp-Generierungsschleifen für verschiedene Metriken einheitlich generiert.
  * **TUI-Komponenten:** Die ASCII-Zeichenfunktionen für Graphen (Braille-Plots) und Tabellenspalten werden über strukturierte Generierungs-Templates erzeugt.

### 2.2. Rendering-Details (Braille-Plots)
* Um historische Daten platzsparend anzuzeigen, nutzen wir Unicode-Braille-Zeichen (U+2800 bis U+28FF). Ein einzelnes Zeichen kann ein 2x4-Raster aus Punkten darstellen, wodurch wir hochauflösende Graphen mit extrem wenig Zeichen (und damit minimalem SSH-Traffic) zeichnen können.

---

## 3. Entwickler- & Agenten-Hinweise
1. **Kein ständiges `clear-screen`:** Verwende ANSI-Escapes, um gezielt nur veränderte Zeichen zu überschreiben.
2. **Dateihashing nutzen:** Nutze `write-source` aus `cl-cl-generator`, um bei der Generierung unnötige Schreibvorgänge auf die Disk zu vermeiden (Schonung von mtime).
3. **Erweiterbarkeit:** Neue procfs-Schnittstellen sollten in `gen.lisp` als neue Einträge in den Generierungslisten hinzugefügt werden, um den Parser-Code automatisch erzeugen zu lassen.
