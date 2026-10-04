for i in /home/kiel/stage/cl-rust-generator/examples/29_lowbandwidth/source7_mvp/client/{*.toml,src/*.rs} \
										       /home/kiel/stage/cl-cl-generator/example/13_polyglot_generator/README.md \
										       /home/kiel/stage/cl-cl-generator/example/13_polyglot_generator/SUPPORTED_FORMS.md \
										       /home/kiel/stage/cl-cl-generator/example/13_polyglot_generator/polyglot-generator.md \
										       /home/kiel/stage/cl-cl-generator/example/13_polyglot_generator/examples/02_lowbandwidth/plan/20261004_01_port/prompt.txt
do
    echo "// start of "$i
    cat $i
done


echo "mache einen review von plan/20261004_01_port/prompt.txt. im docker ist der pfad /home/kiel/stage/ auf /workspace/src gemappt. checke ob alle aufgaben konsistenz sind und sich nicht widersprechen. ich moechte das prompt in der struktur behalten, wie es ist - also mit einer klaren aufteilung zwischen generellen regeln und der spezifischen aufgabe. dadurch kann ich es spaeter fuer neue aufgaben wiederverwenden. habe ich etwas im prompt vergessen?  dann mache mir vorschlaege wie ich das prompt anpassen kann. schreibe das korrigierte komplette neue prompt aus. mache die aenderungen so, dass der diff ueberschaubar bleibt"
