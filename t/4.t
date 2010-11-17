# -*- perl -*-
# goto loop next redo
use Config;
use Test::More tests => 2;
my $c = qq($^X -Mblib -MJit);
my $dbg = $Config{ccflags} =~ /-DDEBUGGING/;
my $thr = $Config{useithreads};

my $e = "t/_t4_1.pl";
my $script = <<'EOF';
my $count = 0;
my $cond = 1;
for (1) {
    if ($cond == 1) {
	$cond = 0;
	goto OTHER;
    }
    elsif ($cond == 0) {
      OTHER:
	$cond = 2;
	is($count, 0, 'OTHER');
	$count++;
	goto THIRD;
    }
    else {
      THIRD:
	is($count, 1, 'THIRD');
	$count++;
    }
}
$count == 2 ? print "ok 1\n" : print "not ok 1\n";
EOF

open F, ">", $e;
print F $script;
close F;
#END { unlink $e; }

my $p = qq( -e $e );
$c .= " -Dv" if $dbg and $] > 5.008;
print "# gdb --args $c $p\n" if $dbg;
ok (`$c $p`, "end of loop");

$e = "t/_t4_2.pl";
$script = <<'EOF';
for(my $i=0;!$i++;) {
  my $x = 1;
  goto label;
  label: $x == 1 ? print "ok 3\n" : print "not ok 3\n";
}
EOF

open F, ">", $e;
print F $script;
close F;
#END { unlink $e; }

$p = qq( -e $e );
print "# gdb --args $c $p\n" if $dbg;
ok (`$c $p` =~ /^ok/, "goto inside a for(;;) loop body from inside the body");

