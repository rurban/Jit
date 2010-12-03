print "1..2\n"; # -*- perl -*-
use Config;
use File::Spec;
my $X = $^X =~ m/\s/ ? qq{"$^X"} : $^X;
my $blib = $] < 5.008
  ? "-I".File::Spec->catfile("blib","arch")." -I".File::Spec->catfile("blib","lib")
  : "-Mblib";
my $c = qq($X $blib -MJit);
$c .= " -Dv" if $Config{ccflags} =~ /-DDEBUGGING/ and $] > 5.008;
print "# ";
for (qw(ptrsize useithreads usemultiplicity gccversion byteorder alignbytes ccflags archname)) {
  print "$_=", defined $Config{$_} ? $Config{$_} : '',", ";
}
print "\n";
#TODO print result of memalign checks for cpantester reports

my $p = q( -e "print q(ok 1);");
print "# gdb --args $c $p\n";
print "# (gdb) run; bt; b Jit.xs: (runops_jit_0); run; disassemble runops_jit_0; stepi;\n";

# check stdout
$r = `$c $p`;
my $childerr = $? >> 8;
print $r,"\n";
if ($r !~ /ok 1/m) {
  print "not ok 1 # print ok op missing\n";
}

# check the exit code
print $childerr ? ("not ok 2 # exitcode $childerr\n") : "ok 2\n";
