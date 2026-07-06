# Tasks - Gentoo Dockerfile Meta-Generator Implementation

- [x] Copy configuration files from the python generator workspace
- [x] Implement variables and helper functions at the top of `gen_gentoo.lisp`
- [x] Revise dynamic portage configuration generations (make.conf, package.use, package.accept_keywords, package.env)
- [x] Implement OpenRC user scripts and services inline heredocs
- [x] Implement the main Dockerfile DSL generation logic with conditional targets and stages
- [x] Add the validation step (`eix-test-obsolete`) and scratch exporter stage
- [x] Generate the `build.sh` and `enter_container.sh` scripts
- [x] Generate a detailed test instruction prompt for the external agent
- [x] Verify compilation of `gen_gentoo.lisp` and output Dockerfile syntax
