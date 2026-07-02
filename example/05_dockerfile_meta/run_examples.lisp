(eval-when (:compile-toplevel :execute :load-toplevel)
  (let ((current-dir (make-pathname :directory (pathname-directory *load-pathname*))))
    (load (merge-pathnames "source01/examples/01_gentoo/gen_gentoo.lisp" current-dir))
    (load (merge-pathnames "source01/examples/02_agy_env/gen_agy_env.lisp" current-dir))))
