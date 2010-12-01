# -*- perl -*-
use Config;
use File::Spec;
my $X = $^X =~ m/\s/ ? qq{"$^X"} : $^X;
my $blib = "-I".File::Spec->catfile("blib","arch")." -I".File::Spec->catfile("blib","lib");
my $c = qq($X $blib -MJit);
my $dbg = $Config{ccflags} =~ /-DDEBUGGING/;
my $thr = $Config{useithreads};
my $have_dispatch = ($] > 5.006 and $] < 5.013) ? 1 : 0; #problem with HAVE_DISPATCH
print "1..2\n";

my $p = q( -e 'my $a=1; my $ok="ok 1\n";if($a>2){print q(nok ),$ok; } else { print $ok; }' );
$c .= " -Dv" if $dbg and $] > 5.008;

print "# gdb --args $c $p\n" if $dbg;
print !system(qq($c $p)) ? " #" : "not ok 1 #";
# problem with HAVE_DISPATCH. first is other, then next
print " TODO" if $thr or $have_dispatch;
print " - 2nd branch next";
print "\n";

$p = q( -e 'my $a = 1; if ($a < 2) { print q(ok 2); } else { print q(not ok 2); }' );
print "# gdb --args $c $p\n" if $dbg;
print !system(qq($c $p)) ? " #" : "not ok 2 #";
print " TODO" if $have_dispatch;
print " - 1st branch other";
print "\n";
