#!/usr/bin/perl
# make OPTIMIZE="-O3 -DPROFILING" && perl -Mblib t/bench.pl

my $X = $^X =~ m/\s/ ? qq{"$^X"} : $^X;
my $script = "benchtest.pl";

open F, ">", $script;
print F 'my $a=1; my $b=6;',"\n";
for (1..1000) { print F '$a += $b*2 - 3; $b -= 1;',"\n"};
print F 'print $a;',"\n";
close F;

my $c = "time $X -Mblib -MJit $script";
print $c,"\n";
system($c);
$c = "time $X $script";
print $c,"\n";
system($c);

#END  { unlink $script; }
