use ExtUtils::MakeMaker;
use Config;
use File::Spec;
use ExtUtils::Embed qw(ccopts ldopts);

my $core = grep { $_ eq 'PERL_CORE=1' } @ARGV;

my $ccflags = $Config{ccflags};
my $lddlflags = $Config{lddlflags};
if ($^O eq 'darwin') {
  $lddlflags =~ s/-flat_namespace/-twolevel_namespace/;
  $lddlflags =~ s/-undefined suppress/-undefined error/;
  $lddlflags .= " $Config{archlibexp}/CORE/$Config{libperl}";
}

# Check for memalign, posix_memalign
my $obj = $Config{obj_ext};
sub check_cc {
  my $sym = shift;
  open C, ">", "test.c";
  print C << "EOF";
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

int main (int argc, char **argv) {
pTHXx;
$sym;
}
EOF
  close C;

  my $cflags = ccopts;
  my $exe = $Config{exe_ext};
  my $redir = $^O eq 'MSWin32' ? "> NUL" : "2>&1 >/dev/null";
  print "\nTesting $sym\n";

  my $coredir = $ENV{PERL_SRC} || "$Config{installarchlib}/CORE";
  my $libdir  = "$Config{prefix}/lib";
  my $useshrplib = $Config{useshrplib};
  my $linkargs;
  if ($^O eq 'MSWin32' && $Config{cc} =~ m/^cl/i) { # yet unused
    my $cmd = "$Config{cc} $cflags -c";
    print "$cmd\n";
    system($cmd);
    my $ok = ($? == 0) and -e "test.obj";
    return 0 unless $ok;

    $linkargs = ldopts("-std");
    $linkargs .= " perl5$Config{PERL_VERSION}.lib kernel32.lib msvcrt.lib";
    $cmd = "$Config{ld} test.obj $linkargs $redir";
    print "$cmd\n";
    system $cmd;
  }
  else {
    if ( -e "$coredir/$Config{libperl}" and $Config{libperl} !~ /\.(dll|so)$/ ) {
      # prefer static linkage manually, without broken ExtUtils::Embed
      $linkargs = sprintf("%s $coredir/$Config{libperl} %s",
			  @Config{qw(ldflags libs)});
    } elsif ( $useshrplib and -e "$libdir/$Config{libperl}") {
      # debian: /usr/lib/libperl.so.5.10.1 and broken ExtUtils::Embed::ldopts
      $linkargs = ldopts('-std');
      $linkargs =~ s|-lperl |$libdir/$Config{libperl} |;
    } else {
      $linkargs = ldopts('-std');
    }
    my $cmd = "$Config{cc} $ccflags -I$coredir test.c $linkargs $redir";
    print "$cmd\n";
    system $cmd;
  }
  my $ok = $? == 0;
  print $ok ? " ok\n" : " not found\n";
  return $ok;
}

if ($^O ne 'MSWin32') {
  END { unlink "a.out", "test.exe", "test$obj", "test.c"; };
  if (check_cc("memalign(2048, 1024)")) {
    $ccflags .= " -DHAVE_MEMALIGN";
  } elsif (check_cc("posix_memalign(2048, 1024)")) {
    $ccflags .= " -DHAVE_POSIX_MEMALIGN";
  }
}

WriteMakefile
 (
  NAME	    	=> "Jit",
  VERSION_FROM  => "lib/Jit.pm",
  CCFLAGS       => $ccflags,
  PREREQ_PM => {
    'sigtrap' => 1.00,
  },
  'AUTHOR'   => 'Reini Urban <perl-compiler@googlegroups.com>',
  'ABSTRACT' => 'Jit the perl5 runloop in proper execution order and near calls',
  ($ExtUtils::MakeMaker::VERSION gt '6.46' ?
   ('META_MERGE'  => {
     resources =>
     {
       license     => 'http://dev.perl.org/licenses/',
       repository  => 'http://github.com/rurban/Jit/',
     },
    }
   ) : ()),
  #SIGN  => 1,
  clean => { FILES =>
 	       "*.core *.stackdump a.out *.exe *.dis *.s *.i *.obj *.o ".
               "*.pdb *~ dll.base dll.exp *.err *.bak"
  },
 );

sub MY::depend {
  "
Jit.c : i386.c i386thr.c amd64.c amd64thr.c
t : test
";
}

sub MY::postamble {
  $bit = "_" . $Config{ptrsize} * 8;
  if ($Config{useithreads}) {
    "asm : help/cc_main$bit.dis

help/cc_main$bit.dis: help/cc_main$bit
	objdump -d -S help/cc_main$bit > help/cc_main$bit.dis

help/cc_main$bit: help/cc_main.c
	\$(PERL) -S cc_harness help/cc_main.c -fno-stack-protector -g3 -o help/cc_main$bit -save-temps -fverbose-asm
"
  } else {
    "asm : help/cc_main_nt$bit.dis help/3-jit-hand.dis

help/cc_main_nt$bit.dis: help/cc_main_nt$bit
	objdump -d -S help/cc_main_nt$bit > help/cc_main_nt$bit.dis

help/cc_main_nt$bit: help/cc_main_nt.c
	\$(PERL) -S cc_harness help/cc_main_nt.c -fno-stack-protector -g3 -o help/cc_main_nt$bit -save-temps -fverbose-asm

help/3-jit-hand.dis: help/3-jit-hand.S
	as help/3-jit-hand.S -o help/3-jit-hand.o
	objdump -d help/3-jit-hand.o > help/3-jit-hand.dis
"
  }
}
