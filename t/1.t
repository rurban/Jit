print "1..1\n"; # -*- perl -*-
use Config;
use File::Spec;
my $X = $^X =~ m/\s/ ? qq{"$^X"} : $^X;
my $blib = "-I".File::Spec->catfile("blib","arch")." -I".File::Spec->catfile("blib","lib");
my $c = qq($X $blib -MJit);
$c .= " -Dv" if $Config{ccflags} =~ /-DDEBUGGING/ and $] > 5.008;
print "# ";
for (qw(ptrsize useithreads usemultiplicity gccversion byteorder alignbytes ccflags archname)) {
  print "$_=",exists $Config{$_} ? $Config{$_} : '',", ";
}
print "\n";
#TODO print result of memalign checks for cpantester reports

my $p = q( -e "print q(ok 1);");
print "# gdb --args $c $p\n";
print "# (gdb) run; bt; b Jit.xs: (runops_jit_0); run; disassemble runops_jit_0; stepi;\n";
print system(qq($c $p)) ? "not ok 1" : "";
print "\n";
