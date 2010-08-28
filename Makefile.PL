use ExtUtils::MakeMaker;
use Config;
use File::Spec;

my $core = grep { $_ eq 'PERL_CORE=1' } @ARGV;

WriteMakefile(
  NAME	    => "Jit",
  VERSION_FROM    => "lib/Jit.pm",
  PREREQ_PM => {
    'sigtrap' => 1.00,
  },
  'AUTHOR'   => 'Reini Urban <perl-compiler@googlegroups.com>',
  ($ExtUtils::MakeMaker::VERSION gt '6.46' ?
   ('META_MERGE'  => {
     resources =>
     {
       license     => 'http://dev.perl.org/licenses/',
       repository  => 'http://github.com/rurban/Jit/',
     },
    }
   ) : ()),
  SIGN  => 1,
  clean => { FILES =>
 	       "*.core *.stackdump a.out *.exe *.dis *.s *.i *.obj *.o ".
               "*.pdb *~ dll.base dll.exp *.err *.bak"
  },
);

sub MY::depend {
  "Jit.c : i386.c i386thr.c amd64.c amd64thr.c\n";
}

sub MY::postamble {
  if ($Config{useithreads}) {
    "asm : help/cc_main.dis

help/cc_main.dis: help/cc_main
	objdump -d -S help/cc_main > help/cc_main.dis

help/cc_main: help/cc_main.c
	\$(PERL) -S cc_harness help/cc_main.c -fno-stack-protector -g3 -o help/cc_main -save-temps -fverbose-asm
"
  } else {
    "asm : help/cc_main_nt.dis

help/cc_main_nt.dis: help/cc_main_nt
	objdump -d -S help/cc_main_nt > help/cc_main_nt.dis

help/cc_main_nt: help/cc_main_nt.c
	\$(PERL) -S cc_harness help/cc_main_nt.c -fno-stack-protector -g3 -o help/cc_main_nt -save-temps -fverbose-asm
"
  }
}
