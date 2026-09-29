#Q:
koennte man im transpiler einen borrow checker fuer c++ code einbauen? aendere keinen code. antworte nur auf meine frage

#A:
• Ja, aber nicht für beliebigen C++-Code, sondern für die DSL, aus der das C++ entsteht. Der Transpiler liest kein C++. Er erzeugt es aus der IR, und genau dort wäre ein
  Borrow-Checker gut machbar.

  Warum es in der IR realistisch ist

  Die IR hat vieles nicht, was Borrow-Checking in C++ unentscheidbar macht: keine Zeigerarithmetik, keine rohen Zeiger, kein goto, keine Überladung und keine Templates. Was
  ein Checker braucht, liegt dagegen schon vor:
  - Typen und Parameter-Modi (:in, :inout, :sink) sind explizit.
  - Regionen und borrows-from gibt es bereits im Typsystem ((:view T region)).
  - Der check-Pass prüft schon Teile davon: E5 (Besitz und Move, auch für :sink), dass :in-Parameter nur gelesen werden, und K1b (mehrdeutige Borrows).
  - Der mutability-Pass weiß bereits, welche Variablen verändert werden.

  Es fehlt eine Datenfluss-Analyse im Stil von Rusts NLL: Welche Ausleihe lebt an welcher Stelle, und kollidiert sie mit einer Veränderung oder einem Move? Damit würde man
  die typischen C++-Fehler finden, die im erzeugten Code heute möglich wären:
  - eine std::string_view, die länger lebt als ihr std::string,
  - push auf einen Vektor, während darüber iteriert wird (ungültige Iteratoren),
  - Zugriff auf eine Variable nach std::move,
  - eine :inout-Referenz, während derselbe Wert noch geliehen ist.

  Den Aufwand schätze ich grob auf einen neuen Pass mit ungefähr 1000–2000 Zeilen, ähnlich groß wie resolve. Das ist nicht verifiziert.

  Es gibt heute schon einen indirekten Borrow-Checker

  Dieselbe IR erzeugt auch Rust, und die Integrationstests lassen cargo clippy darüber laufen. Kompiliert die Rust-Fassung, dann hat rustc die Ausleihen des Programms
  geprüft. Die C++-Fassung entsteht aus derselben IR mit denselben Modi, also gilt das praktisch auch für sie. Der Nachteil: Die Fehlermeldungen kommen von rustc und
  beziehen sich auf Rust-Code, nicht auf die DSL. Ein eigener Pass könnte die DSL-Form nennen, weil jeder Knoten seine Quellform kennt.

  Grenzen

  - raw, target-case und defextern sind für den Checker undurchsichtig. Man müsste ihnen vertrauen oder sie annotieren lassen.
  - Die Regeln gelten für alle Backends, weil die DSL gemeinsam ist. Ein Programm, das für Python problemlos wäre, würde dann abgelehnt. Das ist aber schon heute so, weil
  die Rust-Fassung kompilieren muss.
  - Fremden oder handgeschriebenen C++-Code kann man so nicht prüfen. Dafür gibt es nur Teillösungen: Clangs Lifetime-Analyse (-Wdangling, [[clang::lifetimebound]]), das
  Lifetime-Profil der C++ Core Guidelines oder Circles „Safe C++“. Keine davon ist vollständig.

  Was ich vorschlagen würde, vom geringsten zum größten Aufwand

  1. [[clang::lifetimebound]] ausgeben, wo borrows-from steht, zum Beispiel an longest. Das kostet wenig, und Clang warnt dann selbst bei hängenden Views.
  2. ASan/UBSan für das C++-Ziel in run-integration.sh einschalten. Das findet zur Laufzeit, was statisch durchrutscht.
  3. Ein eigener Borrow-Check-Pass in der IR (etwa Order 35, nach check). Er gibt Fehlermeldungen mit DSL-Quellform und macht die Sicherheit unabhängig davon, ob Rust als
  Ziel mitläuft.

  Kurz: Ein echter Borrow-Checker für beliebiges C++ ist nicht machbar, für die DSL des Generators aber schon. Einen großen Teil der Wirkung liefert heute bereits indirekt
  der Rust-Compiler.

  Credits: 3.38 • Time: 39s
