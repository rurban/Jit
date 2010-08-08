print "1..1\n";
print "#",(qq( gdb --args $^X -Mblib -MJit -e 'print "ok"')),"\n";
print "#",(qq((gdb) run; bt; b Jit.xs:411; run; disassemble code code+100; stepi;')),"\n";
system(qq($^X -Mblib -MJit -e 'print "ok"'));
