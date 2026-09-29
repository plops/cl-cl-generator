for i in /home/kiel/stage/{cl-cl-generator,cl-cpp-generator2,cl-py-generator,cl-rust-generator}/*.lisp
do
    echo "// start of "$i
    cat $i
done
