print "1..2\n";
my $c = qq($^X -Mblib -MJit);

my $p = qq( -e 'print "ok"');
print "#",(qq( gdb --args $c $p')),"\n";
print "#",(qq((gdb) run; bt; b Jit.xs:411; run; disassemble code code+100; stepi;')),"\n";
system(qq($c $p));
print "\n";

$p = qq( -e 'sub f{print "ok"}; f;');
print "#$c $p\n";
system(qq($c $p));
print " #TODO\n";
