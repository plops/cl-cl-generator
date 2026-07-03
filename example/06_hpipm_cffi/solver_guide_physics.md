# Leitfaden für Physiker: Optimale Steuerung und das HPIPM High-Level-Interface

Dieser Leitfaden erklärt das High-Level Lisp-Interface zur optimalen Steuerung (Model Predictive Control, MPC) und dem HPIPM-Solver. Er richtet sich an Physiker und setzt keine Vorkenntnisse in Regelungstechnik (Control Theory) oder numerischer Optimierung voraus. 

---

## 1. Die physikalische Analogie: Vom Prinzip der kleinsten Wirkung zur optimalen Steuerung

In der Physik beschreibt man dynamische Systeme meist über Differentialgleichungen (z. B. die Newtonschen Bewegungsgleichungen). Um den Zustand eines Systems zu steuern, üben wir äußere Kräfte oder Felder aus.

### Die Akteure: Zustände und Stellgrößen
*   **Zustand (State, $x$):** Der komplette physikalische Zustand des Systems zu einem Zeitpunkt. Bei einer Punktmasse besteht $x$ beispielsweise aus Ort $q$ und Impuls $p$ (oder Geschwindigkeit $v$).
*   **Stellgröße (Control, $u$):** Die externe Kraft, das Drehmoment oder die Spannung, mit der wir aktiv in das System eingreifen, um es zu lenken.

### Das Prinzip: Minimierung eines Energie- oder Strafterms
Das Prinzip der kleinsten Wirkung besagt, dass die Natur Pfade wählt, die das Integral der Lagrange-Funktion minimieren. In der optimalen Steuerung machen wir etwas Ähnliches, allerdings künstlich: 
Wir definieren ein Funktional – die **Kostenfunktion** (Cost Function) –, das wir minimieren wollen. Typischerweise wollen wir:
1.  Den Abstand zum Zielzustand minimieren (z. B. das Pendel soll senkrecht stehen: Auslenkung $\approx 0$).
2.  Die eingesetzte Steuerenergie (z. B. Kraftstoffverbrauch, Joulesche Wärme der Aktuatoren) minimieren.

Die mathematische Formulierung über einen Zeithorizont $N$ lautet:
$$ J = \sum_{k=0}^{N-1} (x_k^T Q x_k + u_k^T R u_k) + x_N^T Q_N x_N $$
*   **$Q$:** Gewichtung der Zustandsabweichung (stellt eine Art "Potenzialtopf" um den Nullpunkt dar).
*   **$R$:** Gewichtung der Steuerenergie (bestraft zu hohe Kräfte, analog zur Begrenzung von kinetischer/thermischer Verlustleistung).

---

## 2. Model Predictive Control (MPC): Kontinuierliches Vorausschauen

Model Predictive Control (Modellprädiktive Regelung) funktioniert wie folgt:
1.  **Messen:** Bestimme den aktuellen physikalischen Zustand $x_0$ des Systems.
2.  **Vorausberechnen (Prädiktion):** Berechne über einen endlichen Zeithorizont von $N$ Zeitschritten die optimale Abfolge von Kräften ($u_0, u_1, \dots, u_{N-1}$), die das System unter Einhaltung aller physikalischen Grenzen optimal zum Ziel führt.
3.  **Anwenden:** Wende nur den allerersten berechneten Kraftschritt $u_0$ auf das reale System an.
4.  **Wiederholen:** Im nächsten Zeitschritt misst man erneut und wiederholt die Optimierung mit verschobenem Horizont.

---

## 3. Dynamik und Diskretisierung

Da Computer in diskreten Zeitschritten $\Delta t$ arbeiten, übersetzen wir kontinuierliche Differentialgleichungen der Form:
$$ \dot{x}(t) = A_c x(t) + B_c u(t) $$
in diskrete Differenzengleichungen (Zeitevolution):
$$ x_{k+1} = A x_k + B u_k $$
*   **$A$:** Die freie Zeitevolution des Systems (analog zum Propagator in der Quantenmechanik über die Zeitdauer $\Delta t$).
*   **$B$:** Der Einfluss der externen Kraft auf die Änderung des Zustands im nächsten Schritt.

---

## 4. Beschränkungen (Constraints) und elastische Grenzen

In realen Systemen sind wir durch physische Gegebenheiten eingeschränkt: Motoren können nur eine maximale Kraft aufbringen, Ventile können nur voll geöffnet sein, oder ein Wagen darf sich nur auf einer Schiene definierter Länge bewegen.

### Hard Constraints (Harte Schranken)
Dies sind unüberwindbare Grenzen (z. B. $u_{min} \le u_k \le u_{max}$). HPIPM garantiert, dass diese Schranken exakt eingehalten werden. 
*   *Problem:* Startet ein System außerhalb dieser Grenzen (oder wird durch eine externe Störung dorthin gestoßen), besitzt das mathematische Optimierungsproblem keine zulässige Lösung (infeasible). Der Solver bricht mit einem Fehler ab.

### Soft Constraints (Weiche Schranken / Slack-Variablen)
Um Systemabstürze bei unvorhergesehenen Störungen zu verhindern, nutzen wir **Soft Constraints**. Wir erlauben eine Verletzung der Grenzen, bestrafen diese jedoch extrem stark in der Kostenfunktion.
Mathematisch führen wir dafür Hilfsvariablen $s_l, s_u \ge 0$ (sogenannte **Slack-Variablen**) ein:
$$ x_{min} - s_l \le x_k \le x_{max} + s_u $$
Die Kostenfunktion wird um einen quadratischen Term $s^T Z s$ und einen linearen Term $z^T s$ erweitert. Sobald das System die Grenze überschreitet, verhält sich das Soft Constraint wie eine sehr steife Feder (Federkonstante $Z$), die das System elastisch, aber bestimmt in den zulässigen Bereich zurückzieht.

---

## 5. Mathematische Werkzeuge im Hintergrund verständlich erklärt

Um die quadratischen Optimierungsprobleme (QP) extrem schnell in Echtzeit zu lösen, nutzt HPIPM bewährte numerische Verfahren. Hier sind die wichtigsten Konzepte kurz erklärt:

### Interior-Point-Methode (IPM)
Die Interior-Point-Methode (Innere-Punkte-Methode) löst Optimierungsprobleme mit Ungleichungen, indem sie die Grenzen durch stetige "Barrierefunktionen" (z. B. logarithmische Potenziale der Form $-\mu \ln(c(x))$) ersetzt. Diese Barrieren wirken wie repulsive Potenziale, die gegen unendlich streben, je näher man der Grenze kommt. Während des Algorithmus wird die Stärke $\mu$ der Barriere schrittweise gegen Null gefahren, sodass man sich der exakten Lösung von der Innenseite des zulässigen Bereichs her annähert.

### Cholesky-Zerlegung (Cholesky Decomposition)
Um im Optimierungsschritt Gleichungssysteme der Form $M y = b$ zu lösen, zerlegt man die symmetrische, positiv definite Matrix $M$ (welche die Trägheit und die Krümmung der Kostenfunktion beschreibt) in das Produkt einer unteren Dreiecksmatrix $L$ und deren Transponierten:
$$ M = L L^T $$
Dies ist das numerische Äquivalent zum Ziehen einer Quadratwurzel für Matrizen. Da $L$ eine Dreiecksmatrix ist, lässt sich das System $L (L^T y) = b$ extrem effizient durch einfaches Vorwärts- und Rückwärtseinsetzen lösen. Das spart im Vergleich zu einer vollen Matrixinversion massiv Rechenzeit.

### QR-Zerlegung (QR Decomposition)
Die QR-Zerlegung faktorisiert eine beliebige Matrix $A$ in das Produkt einer orthogonalen Matrix $Q$ (die Längen und Winkel erhält, analog zu Rotationen im Raum) und einer oberen Dreiecksmatrix $R$:
$$ A = Q R $$
In der Optimierung wird dies genutzt, um lineare Abhängigkeiten von Zwangsbedingungen stabil zu behandeln und Projektionen in den physikalisch zulässigen Unterraum verlässlich zu berechnen, selbst wenn die Matrizen numerisch schlecht konditioniert (nahezu singulär) sind.

---

## 6. Das High-Level Lisp API Referenzhandbuch

Das Common Lisp Interface kapselt die komplexen Speicherstrukturen in einem übersichtlichen Workflow:

### 1. Solver erzeugen: [make-mpc-solver](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/hpipm-high.lisp#L42)
Erstellt das Solver-Objekt und allokiert den 64-Byte-ausgerichteten Speicher.
```lisp
(make-mpc-solver
  :horizon N                ; Zeithorizont (Anzahl Schritte)
  :nx nx                    ; Dimension des Zustandsvektors (z.B. 4)
  :nu nu                    ; Dimension des Stellgrößenvektors (z.B. 1)
  :soft-constraints list    ; Optionale Soft-Constraints-Liste
  :precision :double)       ; :double oder :single Precision
```

Die Angabe von Soft-Constraints erfolgt deklarativ als Liste von Eigenschaftslisten (plists):
```lisp
:soft-constraints '((:stage :all :type :state :index 2 :Z 1e4 :z 0.0))
```
*   `:stage`: Spezifiziert die Stufe (`:all` für den gesamten Horizont, `:terminal` für Stufe $N$, `:path` für $0\dots N-1$, oder ein konkreter Index).
*   `:type`: `:state` (Zustände), `:input` (Stellgrößen) oder `:general` (allgemeine Kopplungen).
*   `:index`: Nullbasierter Index der betroffenen physikalischen Variable.
*   `:Z`: Quadratische Strafe (Federsteifigkeit).
*   `:z`: Lineare Strafe.

### 2. Dynamik definieren: [set-solver-dynamics](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/hpipm-high.lisp#L143)
Definiert die Matrizen $A$ und $B$ für die Zeitevolution über alle Stufen:
```lisp
(set-solver-dynamics solver Ad Bd)
```

### 3. Kostenfunktion setzen: [set-solver-cost](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/hpipm-high.lisp#L162)
Definiert die Strafterme $Q$ (Abweichung vom Ziel) und $R$ (Steuerenergie):
```lisp
(set-solver-cost solver Q R)
```

### 4. Grenzen festlegen:
*   [set-control-bounds](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/hpipm-high.lisp#L169): Legt die harten Kraft- oder Stellgrenzen für einen Kanal fest.
    ```lisp
    (set-control-bounds solver 0 -5.0d0 5.0d0) ; Grenze für Kanal 0 auf [-5, 5]
    ```
*   [set-state-bounds](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/hpipm-high.lisp#L185): Schranken für Zustandsvariablen an einer bestimmten Stufe.
    ```lisp
    (set-state-bounds solver stage indices-list min-list max-list)
    ```
*   [set-general-constraints](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/hpipm-high.lisp#L200) / [set-solver-general-constraints](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/hpipm-high.lisp#L221): Ermöglicht allgemeine lineare Kopplungs-Ungleichungen der Form:
    $$ lg \le C x + D u \le ug $$
    ```lisp
    (set-general-constraints solver stage C D lg ug)
    ```
    *Falls `C` oder `D` `nil` sind, erzeugt das Interface automatisch Nullmatrizen der passenden Dimensionen.*

### 5. Optimieren: [solve-mpc](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/hpipm-high.lisp#L226)
Löst das Optimierungsproblem für den aktuellen Zustand `x0` und gibt 6 Werte zurück:
```lisp
(multiple-value-bind (u-traj x-traj status iterations sl-traj su-traj)
    (solve-mpc solver x0)
  ...)
```
*   `u-traj`: Vektor der optimalen Stellgrößen (Kräfte) pro Schritt.
*   `x-traj`: Vektor der vorausgesagten Systemzustände (Trajektorie).
*   `status`: Rückgabewert des Solvers ($0$ = Konvergiert/Erfolg, $>0$ = Fehler/Nicht konvergiert).
*   `iterations`: Anzahl der benötigten IPM-Schritte.
*   `sl-traj` / `su-traj`: Vektoren der berechneten Slack-Variablen (Verletzungen der unteren/oberen Soft-Constraints).

---

## 7. Anwendungsbeispiel: Gekoppeltes Feder-Masse-Dämpfer-System

Das System besteht aus zwei Wagen auf einer Schiene, die über Federn miteinander gekoppelt sind. Wir steuern den ersten Wagen mit einer Kraft $u$.

Die kontinuierliche Bewegungsgleichung lautet:
$$ m \ddot{q}_1 + d (\dot{q}_1 - \dot{q}_2) + k (q_1 - q_2) = u $$
$$ m \ddot{q}_2 + d (\dot{q}_2 - \dot{q}_1) + k (q_2 - q_1) = 0 $$

Als diskretisiertes Zustandsraummodell mit Zustand $x = [q_1, \dot{q}_1, q_2, \dot{q}_2]^T$:
```lisp
;; Systemmatrizen definieren
(set-solver-dynamics solver Ad Bd)
```

### Soft-Constraints in der Praxis: Der Ausweich-Mechanismus
Wir fordern, dass sich der zweite Wagen nicht weiter als $0.4\,\text{m}$ nach rechts bewegen darf ($q_2 \le 0.4$).
1.  **Harte Begrenzung (Infeasible):** Startet der Wagen bei einer Auslenkung von $0.5\,\text{m}$, scheitert eine harte Begrenzung sofort ($0.5 \le 0.4$ ist falsch).
2.  **Weiche Begrenzung (Soft Constraint):** Der Solver akzeptiert den Startzustand, misst die Überschreitung als Slack ($s_{u} = 0.1\,\text{m}$) und zieht das System durch die Kostenstrafe schnellstmöglich zurück in den zulässigen Bereich.

Das Demo in [mpc-soft-demo.lisp](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/mpc-soft-demo.lisp) veranschaulicht dieses Verhalten im Detail. Zum Ausführen des Demos lädt man das System und ruft auf:
```lisp
(hpipm-soft-demo:run-soft-demo)
```
Dies gibt die berechneten Trajektorien sowie die zeitliche Evolution der Slack-Variablen (Grenzverletzungen) übersichtlich auf dem Terminal aus.
