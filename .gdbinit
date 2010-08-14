#set args -Mblib -MJit -e'print qq(ok);'
#set args -Mblib -MJit -e'sub f{print qq(ok)}; f;'
#directory /usr/src/perl/blead/perl-git
#directory /usr/src/perl/perl-5.10.1/perl-5.10.1
#b Perl_runops_jit y
add-symbol-file run-jit.o 0
