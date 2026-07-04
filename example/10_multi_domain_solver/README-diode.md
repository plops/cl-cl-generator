# Elektro-Thermische Diodensimulation mit Selbsterwärmung

Diese Verzeichnis-Erweiterung von **Beispiel 10** enthält eine voll integrierte, gekoppelte elektro-thermische Diodensimulation. Sie demonstriert, wie nichtlineare physikalische Kopplungen zwischen verschiedenen Domänen (Elektrik und Thermik) mit `cl-cl-generator` in performanten Common-Lisp-Code übersetzt werden.

---

## 1. Physikalisches Modell

Die Simulation modelliert das wechselseitige Zusammenspiel zwischen dem Stromfluss durch eine Halbleiterdiode und der Temperaturentwicklung an ihrer Sperrschicht (Junction).

### A. Elektrische Domäne
Die Schaltung besteht aus einer AC-Spannungsquelle $V_s(t)$, einem strombegrenzenden Vorwiderstand $R_s$ und der Diode $D_1$.

*   **AC-Quelle**: $V_s(t) = \hat{V} \cdot \sin(2\pi f \cdot t)$ mit Amplitude $\hat{V} = 5.0\text{ V}$ und Frequenz $f = 50\text{ Hz}$.
*   **Widerstand**: $R_s = 100\text{ }\Omega$.
*   **Maschengleichung**:
    $$V_s(t) - v_d(t) - R_s \cdot i_d(t) = 0$$

### B. Thermische Domäne
Die Diode erwärmt sich durch die in ihr in Wärme umgesetzte elektrische Leistung (Joule-Effekt) und gibt diese Wärme an einen Kühlkörper sowie die Umgebung ab.

*   **Verlustleistung**: $P_d(t) = v_d(t) \cdot i_d(t)$ (Wärmequelle).
*   **Wärmekapazität der Diode**: $C_{th} = 0.05\text{ J/K}$ (verzögert die Erwärmung).
*   **Thermischer Widerstand**: $R_{th} = 1000\text{ K/W}$ (modelliert die Wärmeabfuhr zur Umgebung).
*   **Umgebungstemperatur**: $T_{amb} = 298.15\text{ K}$ ($25\text{ °C}$).
*   **Thermische Differentialgleichung**:
    $$C_{th} \frac{dT}{dt} + \frac{T - T_{amb}}{R_{th}} = P_d(t)$$

### C. Elektro-Thermische Kopplung
Die Domänen beeinflussen sich gegenseitig über zwei fundamentale physikalische Effekte:
1.  **Elektrik $\to$ Thermik**: Die elektrische Leistung $P_d = v_d \cdot i_d$ heizt die Diode auf.
2.  **Thermik $\to$ Elektrik**: Die Temperatur $T$ verändert das elektrische Verhalten der Diode gemäß der Shockley-Gleichung:
    $$i_d(v_d, T) = I_s(T) \cdot \left( e^{\frac{v_d}{\eta \cdot V_T(T)}} - 1 \right)$$
    *   Die **Temperaturspannung** steigt linear: $V_T(T) = \frac{k_B \cdot T}{q} \approx \frac{T}{11600}$.
    *   Der **Sättigungsstrom** steigt exponentiell: $I_s(T) = I_{s0} \cdot e^{\gamma(T - T_0)}$ mit $I_{s0} = 1\text{ pA}$, $T_0 = 298.15\text{ K}$ und $\gamma = 0.07\text{ K}^{-1}$ (ca. Verdoppelung des Stroms je $10\text{ K}$ Temperaturerhöhung).

---

## 2. Mathematische Formulierung & Solver

Zur Diskretisierung der thermischen Ableitung in der Zeit wird das **implizite Euler-Verfahren** (Backward Euler) mit einer Schrittweite $h = \Delta t = 5 \cdot 10^{-4}\text{ s}$ genutzt.

### Nichtlineares System
Wir lösen in jedem Zeitschritt $k$ das folgende nichtlineare Gleichungssystem für die Variablen $x = [v_d, T]^T$:

1.  **KCL-Gleichung (Elektrisch)**:
    $$f_1(v_d, T) = \frac{v_d - V_{s,k}}{R_s} + i_d(v_d, T) = 0$$
2.  **Wärmebilanz (Thermisch)**:
    $$f_2(v_d, T) = \frac{C_{th}}{h} (T - T_{k-1}) + \frac{T - T_{amb}}{R_{th}} - v_d \cdot i_d(v_d, T) = 0$$

### Newton-Raphson-Verfahren
Zur Lösung wird eine mehrdimensionale Newton-Raphson-Iteratior-Schleife durchlaufen:
$$x^{(m+1)} = x^{(m)} - J^{-1}(x^{(m)}) \cdot F(x^{(m)})$$

Die Jacobi-Matrix $J$ wird symbolisch berechnet:
$$J = \begin{bmatrix} \frac{\partial f_1}{\partial v_d} & \frac{\partial f_1}{\partial T} \\ \frac{\partial f_2}{\partial v_d} & \frac{\partial f_2}{\partial T} \end{bmatrix}$$

Mit den partiellen Ableitungen des Diodenstroms:
*   $\frac{\partial i_d}{\partial v_d} = \frac{I_s(T)}{V_T(T)} e^{\frac{v_d}{V_T(T)}}$
*   $\frac{\partial i_d}{\partial T} = \gamma \cdot i_d(v_d, T) - I_s(T) \frac{v_d}{T \cdot V_T(T)} e^{\frac{v_d}{V_T(T)}}$

Daraus ergeben sich die Einträge der Jacobi-Matrix:
*   $\frac{\partial f_1}{\partial v_d} = \frac{1}{R_s} + \frac{\partial i_d}{\partial v_d}$
*   $\frac{\partial f_1}{\partial T} = \frac{\partial i_d}{\partial T}$
*   $\frac{\partial f_2}{\partial v_d} = -i_d - v_d \frac{\partial i_d}{\partial v_d}$
*   $\frac{\partial f_2}{\partial T} = \frac{C_{th}}{h} + \frac{1}{R_{th}} - v_d \frac{\partial i_d}{\partial T}$

Da es sich um ein $2\times2$-System handelt, wird das System analytisch über die Determinante gelöst:
$$\Delta v_d = \frac{- \frac{\partial f_2}{\partial T} f_1 + \frac{\partial f_1}{\partial T} f_2}{\det(J)}$$
$$\Delta T = \frac{\frac{\partial f_2}{\partial v_d} f_1 - \frac{\partial f_1}{\partial v_d} f_2}{\det(J)}$$

**Numerische Stabilisierung**: Um numerische Überläufe durch exponentielles Wachstum in der Anfangsphase zu verhindern, werden die Iterationsschritte geklippt:
$$\Delta v_{d,\text{lim}} = \text{clamp}(-0.05, \Delta v_d, 0.05)$$
$$\Delta T_{\text{lim}} = \text{clamp}(-2.0, \Delta T, 2.0)$$

---

## 3. Code-Generierungs-Pipeline

Die Implementierung nutzt die Stärken von Lisp als Code-Generator:
1.  **[generate-diode-solver.lisp](file:///workspace/src/cl-cl-generator/example/10_multi_domain_solver/generate-diode-solver.lisp)** definiert die Code-Generierungs-Logik unter Verwendung von `cl-cl-generator`.
2.  Beim Start lädt das GUI-Skript diese Datei und ruft `(generate-diode-solver-file "diode-solver" :directory output-dir)` auf, wobei `output-dir` auf das Unterverzeichnis `source01/` zeigt.
3.  Dies erzeugt die Datei `source01/diode-solver.lisp`, welche die allokationsfreie und hochoptimierte Lisp-Struktur `sim-state` sowie die Iterationsschleife in `step-simulation` enthält.
4.  Diese generierte Datei wird anschließend geladen und ausgeführt.

---

## 4. Grafische Oberfläche (GUI)

Die interaktive X11-Benutzeroberfläche in **[diode-gui.lisp](file:///workspace/src/cl-cl-generator/example/10_multi_domain_solver/diode-gui.lisp)** visualisiert das System auf beeindruckende Weise:

### A. Schaltplan & Animation
*   **Elektrischer Kreis**: Zeigt die AC-Spannungsquelle (mit animierter Sinuswelle), den Widerstand und die Diode.
*   **Wärme-Kopplung**: Zeigt den Pfad zum Kühlkörper (Finnen-Symbol) und die gemessene Sperrschichttemperatur $T_j$.
*   **Dynamische Wärme-Aura**: Um die Diode herum pulsiert eine rote Kreisfläche, deren Radius direkt proportional zur aktuellen Temperaturdifferenz ($\Delta T$) wächst.

### B. Live-Oszilloskope (Rolling Plots)
Das untere Drittel des Fensters zeigt drei synchrone Echtzeit-Plots:
1.  **Spannungen**: Die Quellspannung $V_s$ (grün, rein sinusförmig) und die Diodenspannung $V_d$ (orange). Man sieht deutlich die Einweggleichrichtung und die Durchlassspannung von ca. $0.6-0.7\text{ V}$.
2.  **Diodenstrom**: Der Strom $I_d$ (blau, fließt nur in positiven Halbwellen).
3.  **Temperatur**: Die Sperrschichttemperatur $T_j$ (rot). Sie steigt nach dem Start der Simulation kontinuierlich von $25\text{ °C}$ an und nähert sich asymptotisch einem Fließgleichgewicht (ca. $40-45\text{ °C}$), wobei man die kleinen Temperaturwellen im Rhythmus des Wechselstroms (Erwärmungsphasen im Durchlassbetrieb, Abkühlung im Sperrbetrieb) erkennen kann.

---

## 5. Ausführen der Simulation

### Voraussetzungen
*   **SBCL** (Steel Bank Common Lisp)
*   **Quicklisp**
*   Laufendes X11-System (z. B. XQuartz unter macOS oder nativer X-Server unter Linux)

### Starten
Führen Sie das Startskript direkt aus:
```bash
./example/10_multi_domain_solver/run-diode-gui.sh
```

Über die Schaltflächen der GUI kann die Simulation pausiert, zurückgesetzt oder fortgesetzt werden.
