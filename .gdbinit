#set args -Mblib -MJit -e'sub f{print "ok"}; f;'
file run-jit.o
#directory /usr/src/perl/perl-5.10.1/perl-5.10.1
#b Perl_runops_jit
