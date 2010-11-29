print "1..1\n"; # -*- perl -*-
use Config;
use File::Spec;
my $X = $^X =~ m/\s/ ? qq{"$^X"} : $^X;
my $blib = "-I".File::Spec->catfile("blib","arch")." -I".File::Spec->catfile("blib","lib");
my $c = qq($X $blib -MJit);
my $DEBUGGING = $Config{ccflags} =~ /-DDEBUGGING/;
$c .= " -Dv" if $DEBUGGING and $] > 5.008;
my $thr = $Config{useithreads};
#$c .= " -Dv" if $DEBUGGING;

$p = q( -e "sub f{die q(ok 1)}; f; print q(not ok 1)");
print "# gdb --args $c $p\n";
$r = `$c $p`;
if ($r =~ /ok 1/m) {
  print $r;
} else {
  print "not ok 1";
}
print " #TODO entersub\n";
