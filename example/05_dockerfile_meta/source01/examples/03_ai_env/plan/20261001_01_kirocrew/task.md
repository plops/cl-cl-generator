# KiroCrew in der NVIDIA-CUDA-Entwicklungsumgebung

## Ziel und Randbedingungen

KiroCrew wird in die bestehende, aus `gen_ai_env.lisp` erzeugte Entwicklungsumgebung integriert. Das Basisimage bleibt das konfigurierbare Ubuntu-26/NVIDIA-CUDA-Image. KiroCrew- und kiro-cli-Zustand muss in einem persistenten, für den Host-Benutzer zugänglichen Verzeichnis liegen. Das Gateway soll vom Host erreichbar sein, sein Dashboard bleibt token-geschützt und standardmäßig nur an `127.0.0.1` des Hosts veröffentlicht. Sandbox-Fehler dürfen nicht stillschweigend zu unsandboxierter Agent-Ausführung führen.

Der Container startet ausnahmslos mit der vorhandenen Bash-CMD. KiroCrew ist ein Programm, das bei Bedarf manuell in dieser Bash aufgerufen wird. `kirocrew` startet das Gateway mit YOLO-Freigabe; `kirocrew gateway` erzwingt sie ebenfalls. KiroCrew 0.7.2 bietet für seinen eigenen Terminal-Chat keinen YOLO-Schalter; der bleibt unverändert interaktiv. Das Gateway-Dashboard läuft auf Port 5476 und wird standardmäßig nur auf `127.0.0.1` des Hosts veröffentlicht; `--kirocrew-port` ändert den Host-Port.

Die bereits vorhandenen Änderungen an `gen_ai_env.lisp` und dem generierten `Dockerfile` gehören zur Ausgangslage und sind während der Umsetzung zu bewahren.

## Serielle Arbeitsregel

Jede Aufgabe wird in der angegebenen Reihenfolge abgeschlossen. Erst werden Bash-Start, CLI-Wrapper und Persistenz implementiert, durch Host-Tests und HIL geprüft. Danach folgen Gateway, Host-Erreichbarkeit und Persistenznachweis, jeweils mit Host-Tests und HIL. Dashboard/TUI-Aufgaben folgen erst danach. Ein Schritt gilt erst dann als abgeschlossen, wenn sein konkreter Nachweis in diesem Dokument oder im Walkthrough eingetragen ist. Bei Fehlschlag wird die Implementierung angepasst und derselbe Schritt erneut validiert.

HIL bedeutet *Hardware-in-the-Loop*: Prüfung im tatsächlich laufenden Docker-Container auf diesem Host, einschließlich der relevanten GPU-/Netzwerk-/Dateisystem-Schnittstellen. Es bedeutet nicht, dass echte Modellanfragen ohne Anmeldung oder Zugangsdaten simuliert werden.

## Phase 0 – Bestandsaufnahme und Verträge

- [x] **0.1** `gen_ai_env.lisp`, generiertes `Dockerfile`, vorhandene Run-/Build-/Save-/Cleanup-Skripte, `.env.ai` und `README.md` geprüft. Vorbestehende Feature-Toggles bleiben erhalten; CUDA-Flavour `:devel` ist die aufgabenbedingte Abweichung.
- [x] **0.2** Lokale Recherche und offizielle Installationsdokumentation geprüft. Der Builder pinnt die signierte Version 0.7.2 (Python ≥3.12, installerverwaltetes uv/Python); CLI-Hilfe, YOLO-Gatewayflag, Dashboard-Port 5476, persistenter Datenpfad, Token- und Sandbox-Verhalten wurden im installierten Paket geprüft. 0.7.2 hat für `kirocrew chat` keinen YOLO-Schalter.
- [x] **0.3** `kiro-cli login`/ACP werden unverändert durchgereicht; Wrapper-Mocktest deckt Login, ACP-nahe Verwaltungskommandos und KiroCrew-Tokenkommando ab. Vorheriger Runner-Smoke-Test bestätigte `kiro-cli acp --help`.
- [x] **0.4** Plan auf immer-Bash, manuelles YOLO-Gateway, persistenten Hostpfad und Loopback-Portmapping aktualisiert; Chat-CLI-Grenze dokumentiert.

## Phase A – Bash-Start, CLI-Wrapper und Persistenz

### Implementierung

- [x] **A.1** Eigenen Generator-Schalter für KiroCrew ergänzen; KiroCrew bleibt optional.
- [x] **A.2** KiroCrew 0.7.2 über offiziellen signierten Installer mit CPython 3.12 und SHA-gepinntem `uv` installieren.
- [x] **A.3** Containerstart bleibt immer Bash. `setup02_run.sh` akzeptiert keine Chat-/Gateway-Startmodi mehr. `kirocrew` im Container startet das Gateway manuell mit `--approval yolo`; explizite `kirocrew chat`-Aufrufe bleiben unverändert, weil die CLI 0.7.2 dafür keinen YOLO-Schalter hat. ACP- und Login-Kommandos bleiben direkt erreichbar.
- [x] **A.4** Gateway-Wrapper fügt `--approval yolo` hinzu. Ein expliziter Datenpfad `/root/.kiro/crew-yolo` erlaubt KiroCrew den YOLO-Modus; der Host bindet `~/.kiro/crew-yolo` ein. kiro-cli-Login bleibt unter `~/.local/share/kiro-cli` persistent.
- [x] **A.5** Port 5476 ist standardmäßig nur auf Host-Loopback veröffentlicht; `--kirocrew-port` ändert den Host-Port und der Container startet immer in Bash.

### Host-Tests

- [x] **A.6** Generator ausgeführt; generiertes Dockerfile enthält KiroCrew-Installation und Wrapper.
- [x] **A.7** Gepinnter Installer-Stage installierte signiertes KiroCrew 0.7.2; Versionsausgabe sowie Chat-/Gateway-Hilfen liefen erfolgreich. Vorheriger vollständiger Runner-Build bestätigte zusätzlich ACP-Hilfe.
- [x] **A.8** `test_kirocrew_run_modes.sh` prüft Bash als alleinigen Containerstart, Persistenz-Mounts, standardmäßiges Portmapping und Sandbox-Option und Ablehnung entfernter Startoptionen. `test_kirocrew_wrapper.sh` prüft YOLO-Argumente und unverändertes Login/Token-Passthrough; `test_kirocrew_generation.sh` prüft den erzeugten Dockerfile-Vertrag.
- [x] **A.9** `sh -n setup02_run.sh` sowie `bash -n test_kirocrew_*.sh` erfolgreich; `git diff --check` ohne Beanstandungen.

### HIL-Nachweis

- [ ] **A.10** Aktuelles CUDA-Entwicklungsimage bauen und GPU-Nachweis mit NVIDIA-Runtime wiederholen.
- [x] **A.11** Vorheriges KiroCrew-Testimage: Build-Smoke-Tests und `kiro-cli acp` Hilfe erfolgreich; `nvidia-smi -L` erkannte NVIDIA RTX A4000. Run-Skript-Mounts werden durch A.8 geprüft.
- [ ] **A.12** YOLO-Wrapper im neu gebauten Image und interaktive Anmeldung/Chat mit vorhandenen Credentials nachweisen.

## Betriebsart B – Gateway-Dienst

### Implementierung

- [x] **B.1** Gateway manuell aus der immer laufenden Bash starten; Port 5476 ist veröffentlicht, `--kirocrew-port PORT` ändert nur den Host-Port.
- [x] **B.2** Gateway an einer im Container erreichbaren Adresse binden und konfigurierbaren internen Port 5476 dokumentieren. Host-Port standardmäßig an `127.0.0.1` veröffentlichen; nicht ungefragt für das LAN öffnen.
- [x] **B.3** Dashboard-, kiro-cli- und KiroCrew-Zustand persistent halten. Keine Login-Tokens aus Logs, Prozessargumenten oder Build-Layern preisgeben.
- [x] **B.4** Sandbox-Aktivierung als explizite, geprüfte Entscheidung abbilden: bevorzugt KiroCrew-kompatibles Profil/Host-Konfiguration dokumentieren; bei nicht verfügbarem Sandbox-Backend bleibt Agent-Ausführung deaktiviert, außer der Betreiber setzt eine klar benannte Opt-in-Option.
- [x] **B.5** Health- und Shutdown-Verhalten definieren. Gateway wird als Vordergrundprozess manuell aus Bash gestartet und mit Ctrl-C beendet; der Container selbst bleibt in Bash verfügbar.
- [x] **B.6** Run-Hilfe und README um Gateway-Start, Port, persistente Ablage, Login, Token-Link, LAN/TLS-Hinweise und Sandbox-Entscheidung erweitern.

### Host-Tests

- [ ] **B.7** Generator-Schalterkombinationen prüfen: Kiro CLI ohne KiroCrew, beide gemeinsam und beide deaktiviert. Jede Konfiguration muss ein syntaktisch gültiges Dockerfile ergeben.
- [x] **B.8** Gateway-Startbefehl im Image prüfen; tokenfreie Health-Endpunkte liefern Erfolg und ein geschützter Endpunkt weist nicht authentisierte Zugriffe zurück.
- [x] **B.9** Run-Skript-Argumente für Port und Sandbox-Profil testen; ungültige Werte müssen mit verständlicher Fehlermeldung abbrechen.
- [x] **B.10** Sicherstellen, dass Standardstart weder `--privileged`, `seccomp=unconfined` noch unsandboxierte Ausführung aktiviert und Port-Publishing standardmäßig loopback-gebunden ist.

### HIL-Nachweis

- [ ] **B.11** `test_kirocrew_gateway_integration.sh`: Bash-CMD starten, Gateway manuell mit YOLO ausführen, Loopback-Port prüfen und `/api/health` von einem separaten Host-Netzwerk-Container abrufen. Dieses Docker-Setup kapselt den Docker-Daemon in einer eigenen Netzumgebung; direkter Zugriff aus dem Workspace-Host war hier nicht verfügbar.
- [ ] **B.12** Dashboard/API ohne Token ablehnen lassen und frischen Token-Link wie dokumentiert erzeugen; Token nicht im Walkthrough protokollieren.
- [ ] **B.13** Integrationsprüfung schreibt einen Marker ins KiroCrew-Datenvolume, entfernt den Container, erstellt ihn mit demselben Volume neu und liest den Marker anschließend erfolgreich.
- [ ] **B.14** Sandbox-Probe im tatsächlich verwendeten Docker-Runtime-Profil durchführen. Effektives Backend und Startmeldungen dokumentieren; bei fehlendem Backend nachweisen, dass Agent-Ausführung fail-closed deaktiviert bleibt.
- [ ] **B.15** Container mit und ohne GPU-Flag starten und belegen, dass Gateway-Betrieb sowie bisheriger CUDA-Entwicklungsworkflow nicht beschädigt werden.

## Phase C – Dashboard/TUI erst nach Abschluss von A und B

### Implementierung

- [ ] **C.1** TUI-Vertrag anhand der getesteten CLI festlegen: KiroCrew-Terminalchat bleibt promptbasiert; YOLO-Nutzung erfolgt über das Gateway-Dashboard. Keine Container-Startoption darf KiroCrew statt Bash ausführen.
- [ ] **C.2** Dashboard-Nutzung vom Host dokumentieren: Login im Gateway-Container, Token-Link kurzlebig erzeugen, lokale Browser-URL öffnen; LAN-Nutzung nur mit konfigurierter Origin und empfohlenem TLS-Reverse-Proxy beschreiben.
- [ ] **C.3** Keine Terminal-Launcher-Startoption ergänzen; `setup02_run.sh` muss unabhängig von KiroCrew immer das Dockerfile-Bash-CMD starten. Manuelle KiroCrew-Aufrufe bleiben ein eigener Prozess in dieser Shell.

### Host-Tests

- [ ] **C.4** Oberflächenbefehle und Links in Hilfetexten auf gültige Optionen/Portwerte prüfen; Zugangstoken dürfen nicht statisch eingebettet sein.
- [ ] **C.5** Terminalmodus unter echtem TTY sowie nichtinteraktiv testen: TTY-abhängige Anmeldung weist fehlendes TTY verständlich aus; Gateway bleibt davon unabhängig.

### HIL-Nachweis

- [ ] **C.6** Dashboard im Host-Browser öffnen und authentisierte Sitzung nachweisen; Authentisierungsgrenze und Logout/Tokenablauf prüfen.
- [ ] **C.7** Terminalchat mit TTY durchführen, soweit Zugangsdaten verfügbar sind; andernfalls reproduzierbaren Start bis zur Anmeldegrenze dokumentieren.
- [ ] **C.8** Host-Ports und Origin-Regeln prüfen: lokaler Standardzugriff funktioniert, nicht konfigurierte entfernte Origins werden nicht als erfolgreich ausgewiesen.

## Abschluss, Commit und Walkthrough

- [ ] **D.1** Vollständige Generator-Neuerzeugung durchführen; generiertes Dockerfile muss dem Generator entsprechen. Erforderliche Smoke- und Integrationstests aus A–C vollständig ausführen.
- [ ] **D.2** Alle resultierenden Änderungen reviewen: kein Token, versehentlicher privilegierter Start, unbeabsichtigte Änderung bestehender Schalter oder vergessene generierte Datei.
- [ ] **D.3** Relevante Änderungen committen. Vorhandene, nicht zu dieser Aufgabe gehörende Nutzeränderungen nicht versehentlich aufnehmen; Commit-Hash hier eintragen.
- [ ] **D.4** Danach `walkthrough.md` im selben Planordner auf Deutsch schreiben. Es erklärt exakt den implementierten Stand, testbedingte Architekturänderungen, Learnings und mögliche Erweiterungen sowie die neu ins Docker-Image aufgenommenen Programme/Pakete. Fachbegriffe kurz erläutern, Codebeispiele und Mermaid-Diagramme für Architektur und Datenfluss nutzen. Nur tatsächlich ausgeführte Tests und tatsächliche Ergebnisse nennen.

## Ausführungsprotokoll

| Schritt | Ergebnis/Nachweis | Datum |
|---|---|---|
| 0.1–0.4 | Bestand/Upstream dokumentiert; 0.7.2-CLI-/Installervertrag festgelegt | 2026-10-01 |
| A.6–A.9 | Standard-Generator, cl-dockerfile-generator-Tests (0 Fehler), Wrapper-, Generator-Vertrags- und Run-Skript-Tests erfolgreich | 2026-10-01 |
| A.7 | Gepinnter Installer-Stage installierte KiroCrew 0.7.2; CLI-Smoke erfolgreich | 2026-10-01 |
| B.11/B.13 (früherer Stand) | Gateway-Integration auf dem vorherigen Testimage erfolgreich; aktueller gepinnter Runner-HIL-Nachweis steht aus | 2026-10-01 |
| A.10/A.12, B.11–B.15 | Full CUDA Runner konnte mit verfügbarer Build-Speichermenge nicht gebaut werden (669 MB frei nach gezielter Entfernung eigener Test-/Cache-Artefakte) | 2026-10-01 |
