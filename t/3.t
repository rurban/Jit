print "1..2\n"; # -*- perl -*-
use Config;
my $c = qq($^X -Mblib -MJit);
my $dbg = $Config{ccflags} =~ /-DDEBUGGING/;
my $thr = $Config{useithreads};
#$c .= " -Dv" if $dbg;

my $p = q( -e 'my $a = 1; if ($a > 2) { die "nok ok 1\n"; } else { print q(ok); }' );

print "# gdb --args $c $p\n" if $dbg;
print !system(qq($c $p)) ? " 1" : "not ok 1";
print "\t#", ($thr ? "TODO ":"TODO "),"branch next\n";

$p = q( -e 'my $a = 1; if ($a > 2) { print q(not ok); } else { q(print "ok 2\n"); }' );
my $result = `$c $p`;
if ($result =~ /^ok/) {
  print $result;
} else {
  print "not ok 2\t#TODO maybranch other\n";
}
