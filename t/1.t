print "1..1\n";
use Config;
my $c = qq($^X -Mblib -MJit);
#$c .= " -Dv" if $Config{ccflags} =~ /-DDEBUGGING/;

my $p = q( -e 'print q(ok);');
print "# gdb --args $c $p\n";
print "# (gdb) run; bt; b Jit.xs:411; run; disassemble code code+100; stepi;\n";
print system(qq($c $p)) ? "not ok 1" : " 1";
print " #TODO basic asm (fails with threaded perl)" if $Config{useithreads};
print "\n";
