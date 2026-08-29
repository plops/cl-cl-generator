# Archify in `03_ai_env`

Dieses Beispiel bindet Archify als optionales Feature in das generierte AI-Environment-Dockerimage ein. Die Implementierung liegt zentral in [`gen_ai_env.lisp`](gen_ai_env.lisp); [`Dockerfile`](Dockerfile) ist das daraus erzeugte Ergebnis.

## Optionen

- `*install-archify*` (`t`): installiert den Archify-Codex-Skill, Chrome for Testing, die benötigten Ubuntu-Laufzeitbibliotheken und die Archify-Smoke-Tests.
- `*archify-chrome-build*` (`"stable"`): Chrome-for-Testing-Kanal oder exakte Version, etwa `"140.0.7339.80"`.
- `*enable-tests*` (`t`): schaltet alle Build-time-Smoke-Tests gemeinsam ein oder aus.

`*install-archify*` ist ein All-or-nothing-Schalter. Bei `nil` werden weder Archify-Pakete noch Browser, Umgebungsvariablen oder Smoke-Test-Schritte in das Dockerfile geschrieben.

## Erzeugter Installationsablauf

Wenn Archify aktiviert ist, installiert das Runner-Stage zunächst Node.js/npm und die Chrome-Abhängigkeiten. Danach werden Skill und Browser reproduzierbar an festen Zielorten installiert:

```text
/root/.agents/skills/archify
/opt/archify-browser/<version>/chrome-linux*/chrome
/usr/local/bin/archify-chrome -> versionierter Chrome-Binary
```

Das Image setzt außerdem:

```text
ARCHIFY_CHROME=/usr/local/bin/archify-chrome
ARCHIFY_CHROME_NO_SANDBOX=1
```

Der Browser liegt absichtlich unter `/opt`, weil `/root/.cache` in der `setup02`-Umgebung als Cache-Mount verwendet werden kann. Ein exakter `*archify-chrome-build*`-Wert sollte für reproduzierbare Releases verwendet werden; `stable` folgt dem aktuellen Chrome-for-Testing-Stand.

## Smoke-Tests

Bei aktiviertem `*enable-tests*` prüft der Build:

1. die Existenz des installierten Skills und `archify.mjs`,
2. `archify doctor`,
3. einen echten headless-Chrome-Render von `about:blank`,
4. das Archify-Demo-Rendering in einem temporären Verzeichnis.

Beispiel für Laufzeitprüfungen:

```sh
node /root/.agents/skills/archify/bin/archify.mjs doctor
/usr/local/bin/archify-chrome --headless --no-sandbox --disable-gpu --dump-dom about:blank
```

Archify `visual-check` bleibt ein Laufzeit-/Manuelltest für ausgelieferte Diagramme. Er ist kein Build-Gate, weil Chrome-DevTools-Screenshot-Captures in Container-Builds trotz funktionierendem Browser sporadisch mit `Page.captureScreenshot: Unable to capture screenshot` fehlschlagen können.

## Regenerieren und validieren

```sh
./setup00_generate_dockerfile.sh
sbcl --non-interactive --load gen_ai_env.lisp --eval '(quit)'
```

Für einen Integrationstest kann das erzeugte Image gebaut und geprüft werden:

```sh
docker build -t my-ai-env:archify-test .
docker run --rm my-ai-env:archify-test \
  node /root/.agents/skills/archify/bin/archify.mjs doctor
```

Die vollständige Validierung umfasste außerdem die Generator-Tests, eine deterministische Zweitgenerierung, den Archify-Opt-out (`*install-archify* nil`) ohne verbleibende Archify-Referenzen und einen erfolgreichen Image-Build mit allen aktivierten Smoke-Tests.

