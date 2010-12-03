require 5.006;	#5.5.5 fails somehow in check_cc
use ExtUtils::MakeMaker;
use Config;
use File::Spec;
use ExtUtils::Embed qw(ccopts ldopts);

my $core = grep { $_ eq 'PERL_CORE=1' } @ARGV;

my $libs = $Config{libs};
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
  open C, ">test.c"; #5.6.2: Too many arguments for open at Makefile.PL line 21, near ""test.c";"
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
  } elsif (check_cc("void *p; posix_memalign(&p, 2048, 1024)")) {
    $ccflags .= " -DHAVE_POSIX_MEMALIGN";
  }
}

# check for libdisasm: http://bastard.sourceforge.net/libdisasm.html
# tested with libdisasm-0.23
if (-e "/usr/local/lib/libdisasm.a" and $Config{ccflags} =~ /-DDEBUGGING/) {
  $ccflags .= " -DHAVE_LIBDISASM";
  $libs .= " -ldisasm";
}

my $clean_t = File::Spec->catfile("t", "_t4*.pl")." ";
# $clean_t .= File::Spec->catfile("asm", "*.dis")." ";
$clean_t .= File::Spec->catfile("asm", "*".$Config{obj_ext})." ";
$clean_t .= File::Spec->catfile("asm", "cc_main".$Config{exe_ext})." ";
$clean_t .= File::Spec->catfile("asm", "cc_main_nt".$Config{exe_ext})." ";

WriteMakefile
 (
  NAME	    	=> "Jit",
  VERSION_FROM  => "lib/Jit.pm",
  CCFLAGS       => $ccflags,
  LIBS          => $libs,
  PREREQ_PM => {
    'sigtrap' => 1.00,
  },
  'AUTHOR'   => 'Reini Urban <perl-compiler@googlegroups.com>',
  'ABSTRACT' => 'Jit the perl5 runloop in proper execution order and near calls',
  ($ExtUtils::MakeMaker::VERSION gt '6.46' ?
   ('META_MERGE'  => {
     resources =>
     {
       license      => 'http://dev.perl.org/licenses/',
       repository   => 'http://github.com/rurban/Jit/',
      'MailingList' => 'http://groups.google.com/group/perl-compiler',
     },
    }
   ) : ()),
  #SIGN  => 1,
  clean => { FILES =>
             "*.core *.stackdump a.out run-jit.* *.i ".
             "*".($Config{obj_ext} ? $Config{obj_ext} : ".o")." "
             ."$clean_t *.err *.bak "
             .($^O eq 'MSWin32' ? "*.exe  *.pdb *~ dll.base dll.exp " : "")
  },
 );

sub MY::depend {
  "
Jit.c : i386.c i386thr.c amd64.c amd64thr.c
t : test
";
}

sub MY::postamble {
  $bit = ($Config{useithreads} ? "" : "_nt"). "_" . $Config{ptrsize} * 8;
  "
asm/3-jit-hand$bit.dis: asm/3-jit-hand$bit.S
	as asm/3-jit-hand$bit.S -o asm/3-jit-hand$bit.o
	objdump -d asm/3-jit-hand$bit.o > asm/3-jit-hand$bit.dis

asm : asm/cc_main$bit.dis asm/3-jit-hand$bit.dis

asm/cc_main$bit.dis: asm/cc_main$bit\$(EXE_EXT)
	objdump -d -S asm/cc_main$bit\$(EXE_EXT) > asm/cc_main$bit.dis

asm/cc_main$bit\$(EXE_EXT): asm/cc_main.c
	\$(PERL) -S cc_harness asm/cc_main.c -O2 -fno-stack-protector -g3 -o asm/cc_main$bit\$(EXE_EXT) -save-temps -fverbose-asm
"
}
