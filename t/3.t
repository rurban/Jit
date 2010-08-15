print "1..2\n";
use Config;
my $c = qq($^X -Mblib -MJit);
my $dbg = $Config{ccflags} =~ /-DDEBUGGING/;
#$c .= " -Dv" if $dbg;

$p = q( -e 'my $a = 1; if ($a > 2) { die "nok ok 1\n"; } else { print q(ok); }' );

print "# gdb --args $c $p\n" if $dbg;
print !system(qq($c $p)) ? " 1\n" : "not ok 1 - # branch next\n";

$p = q( -e 'my $a = 1; if ($a > 2) { print q(not ok); } else { q(die "ok 1\n"); }' );
print system(qq($c $p)) ? " 1\n" : "not ok 1  #TODO maybranch other\n";