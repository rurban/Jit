use ExtUtils::MakeMaker;
use Config;
use File::Spec;

my $core = grep { $_ eq 'PERL_CORE=1' } @ARGV;

WriteMakefile(
    NAME	    => "Jit",
    VERSION_FROM    => "lib/Jit.pm",
    'AUTHOR'   => 'Reini Urban <perl-compiler@googlegroups.com>',
    ($ExtUtils::MakeMaker::VERSION gt '6.46' ?
    ('META_MERGE'  => {
                       resources =>
                       {
                        license     => 'http://dev.perl.org/licenses/',
                        repository  => 'http://github.com/rurban/p5-jit/',
                       },
                      }
    ) : ()),
    SIGN  => 1,
    clean => { FILES =>
 	       "*.core *.stackdump a.out *.exe *.dis *.s *.i *.obj *.o ".
               "*.pdb *~ dll.base dll.exp *.err *.bak"
             },
);

sub MY::postamble {
  if ($Config{useithreads}) {
"asm : cc_main.dis

cc_main.dis: cc_main
	objdump -d cc_main > cc_main.dis

cc_main: cc_main.c
	\$(PERL) -S cc_harness cc_main.c -fno-stack-protector -Os -o cc_main -save-temps -fverbose-asm
" 
  } else {
"asm : cc_main_nt.dis

cc_main_nt.dis: cc_main_nt
	objdump -d cc_main_nt > cc_main_nt.dis

cc_main_nt: cc_main_nt.c
	\$(PERL) -S cc_harness cc_main_nt.c -fno-stack-protector -Os -o cc_main_nt -save-temps -fverbose-asm
"
  }
}
