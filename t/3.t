# -*- perl -*-
use Config;
use File::Spec;
my $X = $^X =~ m/\s/ ? qq{"$^X"} : $^X;
my $blib = $] < 5.008
  ? "-I".File::Spec->catfile("blib","arch")." -I".File::Spec->catfile("blib","lib")
  : "-Mblib";
my $c = qq($X $blib -MJit);
my $dbg = $Config{ccflags} =~ /-DDEBUGGING/;
my $thr = $Config{useithreads};
my $have_dispatch = ($] > 5.006 and $] < 5.013) ? 1 : 0; #problem with HAVE_DISPATCH

print "1..4\n";

my $p = q( -e 'my $a=1; my $ok=q(ok 1);if($a>2){print q(nok ),$ok; } else { print $ok; }' );
$c .= " -Dv" if $dbg and $] > 5.008;

print "# gdb --args $c $p\n" if $dbg;
$r = `$c $p`;
my $childerr = $? >> 8;
print $r,"\n";
if ($r !~ /ok 1/m) {
  print "not ok 1";
}
print " #";
print " TODO" if $have_dispatch;
print " 2nd branch next";
print "\n";
print $childerr ? ("not ok 2 # TODO exitcode $childerr\n") : "ok 2\n";
# problem with HAVE_DISPATCH. first is other, then next
# threaded fixed by using -8(%ebp) instead of -8(%esp) for op

$p = q( -e 'my $a = 1; if ($a < 2) { print q(ok 3); } else { print q(not ok 3); }' );
print "# gdb --args $c $p\n" if $dbg;
system(qq($c $p));
print " #";
# print " TODO" if $have_dispatch;
print " 1st branch other";
print "\n";

$childerr = $? >> 8;
print $childerr ? ("not ok 4 # exitcode $childerr\n") : "ok 4\n";
