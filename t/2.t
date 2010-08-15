print "1..1\n";
#use Config;
my $c = qq($^X -Mblib -MJit);
#$c .= " -Dv" if $Config{ccflags} =~ /-DDEBUGGING/;

$p = q( -e 'sub f{die "ok 1"}; f; print "not ok 1"');
print "# gdb --args $c $p\n";
system(qq($c $p));
print " #TODO no optree for sub\n";
