# -*- perl -*-
use Config;
use File::Spec;
my $X = $^X =~ m/\s/ ? qq{"$^X"} : $^X;
my $blib = "-I".File::Spec->catfile("blib","arch")." -I".File::Spec->catfile("blib","lib");
my $c = qq($X $blib -MJit);
my $dbg = $Config{ccflags} =~ /-DDEBUGGING/;
my $thr = $Config{useithreads};
#unless ($dbg) {
#  print "1..0 # SKIP maybranch not yet ready (only tested with DEBUGGING perl)\n";
#  exit;
#} else {
  print "1..2\n";
#}

my $p = q( -e 'my $a = 1; if ($a > 2) { print q(nok ok 1); } else { print q(ok 1); }' );
$c .= " -Dv" if $dbg and $] > 5.008;

print "# gdb --args $c $p\n" if $dbg;
print !system(qq($c $p)) ? " " : "not ok 1 ";
print "# branch next\n";

$p = q( -e 'my $a = 1; if ($a < 2) { print q(ok 2); } else { print q(not ok 2); }' );
#my $result = `$c $p`;
print "# gdb --args $c $p\n" if $dbg;
print !system(qq($c $p)) ? " " : "not ok 2 ";
print "# branch other\n";
#if ($result =~ /^ok/) {
#  print $result,"\n";
#} else {
#  print "not ok 2\t#TODO maybranch other\n";
#}
