for i in `find README.md gen.lisp source01/dock.lisp source01/examples/03_ai_env/{gen*.lisp,Doc*}`;
do
    echo "// start of "$i
    cat $i
done
