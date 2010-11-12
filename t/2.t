print "1..1\n"; # -*- perl -*-
use Config;
my $c = qq($^X -Mblib -MJit);
my $DEBUGGING = $Config{ccflags} =~ /-DDEBUGGING/;
my $thr = $Config{useithreads};
#$c .= " -Dv" if $DEBUGGING;

$p = q( -e 'sub f{die "ok 1"}; f; print "not ok 1"');
print "# gdb --args $c $p\n";
system(qq($c $p));
print " #TODO Perl_pp_leave scopestack block assertion. First enter missing.\n"
  if $DEBUGGING and !$thr;
