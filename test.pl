print "1..1\n";
print "#",(qq($^X -Mblib -MJit -e 'print "ok"')),"\n";
system(qq($^X -Mblib -MJit -e 'print "ok"'));
