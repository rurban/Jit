print "1..2\n";
use Config;
my $c = qq($^X -Mblib -MJit);
$c .= " -Dv" if $Config{ccflags} =~ /-DDEBUGGING/;

my $p = qq( -e 'print q(ok)');
print "# gdb --args $c $p\n";
print "# (gdb) run; bt; b Jit.xs:411; run; disassemble code code+100; stepi;\n";
system(qq($c $p));
print " #TODO threads" if $Config{useithreads};
print "\n";

$p = qq( -e 'sub f{print q(ok)}; f;');
print "# gdb --args $c $p\n";
system(qq($c $p));
print " #TODO no optree for sub\n";
