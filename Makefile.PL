use ExtUtils::MakeMaker;
use Config;
use File::Spec;

my $core = grep { $_ eq 'PERL_CORE=1' } @ARGV;

WriteMakefile(
    NAME	    => "Jit",
    VERSION_FROM    => "lib/Jit.pm",
    #PL_FILES   => {'script/perljit.PL'  => 'script/perljit' },
    PREREQ_PM  => {
		   #'Opcodes'  => '0',
		   #'B::CC' => '1.17',
		  },
    'AUTHOR'   => 'Reini Urban <perl-compiler@googlegroups.com>',
    ($ExtUtils::MakeMaker::VERSION gt '6.46' ?
    ('META_MERGE'  => {
                       resources =>
                       {
                        license     => 'http://dev.perl.org/licenses/',
                        #homepage    => 'http://perl-compiler.googlecode.com',
                        #bugtracker  => 'http://code.google.com/p/perl-compiler/issues',
                        #repository  => 'http://perl-compiler.googlecode.com/svn/',
                        #MailingList => 'http://groups.google.com/group/perl-compiler',
                       },
                      }
    ) : ()),
    SIGN  => 1,
);

sub MY::postamble {
"asm : cc_main.dis cc_main_nt.dis

asm_nt : cc_main_nt.dis

cc_main.dis: cc_main.exe
	objdump -d cc_main.exe > cc_main.dis

cc_main.exe: cc_main.c
	\$(PERL) -S cc_harness cc_main.c -fno-stack-protector -Os -o cc_main.exe -save-temps -fverbose-asm

cc_main_nt.dis: cc_main_nt.exe
	objdump -d cc_main_nt.exe > cc_main_nt.dis

cc_main_nt.exe: cc_main_nt.c
	\$(PERL) -S cc_harness cc_main_nt.c -fno-stack-protector -Os -o cc_main_nt.exe -save-temps -fverbose-asm
"
}
