Ich muss oft Dockerfiles schreiben hier sind beispiele:
~/src/cl-py-generator/example/110_gentoo/openrc/Dockerfile
~/src/cl-py-generator/example/172_docker_agy_env/Dockerfile

Suche online nach der Definition der Syntax und der Semantik von Dockerfiles.
Ich moechte den cl-cl-generator nutzen um common lisp code fuer einen speziellen transpiler aehnlich wie in
../01_meta  ../03_py_meta 
schreiben. Der Transpiler soll Dockerfiles erzeugen, aus einer Spezifikation, die in S Expressions, also mit einer lisp artigen Sprache, angegeben ist. Der Vorteil dieser Sprache soll sein, dass es einfach ist, programmatisch mit Hilfe von Listmakros die Texterzeugung zu steuern. Damit moechte ich zum Beispiel Docker Dateien erzeugen, die bestimmte Features enthalten oder wo man Features ein- und ausschalten kann.

Bisher kenne ich mich aber noch nicht so genau aus mit den Docker Features und der Art von Shell Kommandos, die uebergeben werden koennen. Ich sammle erst einmal die notwendigen Informationen und mache einen Yberblick, wie die SExpression Sprache aussehen knnnnnnnte, OpenDocker Files gut darstellen zu koennen. Insbesonder lange shell script commando sequenzen sollen moeglichst ohne extra spezialbehandlung (escaping) von characteren auskommen und vielleicht auch nicht so viele backslashes enthalten muessen. erzeuge noch keinen code. unterbreite erstmal nur vorschlaege

das neue projekt soll cl-dockerfile-generator heissen
