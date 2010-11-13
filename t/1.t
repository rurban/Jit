print "1..1\n"; # -*- perl -*-
use Config;
my $c = qq($^X -Mblib -MJit);
$c .= " -Dv" if $Config{ccflags} =~ /-DDEBUGGING/ and $] > 5.008;

my $p = q( -e 'print qq(ok 1\n);');
print "# gdb --args $c $p\n";
print "# (gdb) run; bt; b Jit.xs:683 (runops_jit_0); run; disassemble runops_jit_0; stepi;\n";
print system(qq($c $p)) ? "not ok 1\n" : "";
