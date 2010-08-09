/* #define PERL_CORE */
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

static OP * pp_main(register PerlInterpreter* my_perl);

#if (PERL_VERSION > 6) && (PERL_VERSION < 13)
#  define PERL_ASYNC_CHECK if (PL_sig_pending) Perl_despatch_signals(aTHX)
# else
#  define PERL_ASYNC_CHECK
#endif

static OP * pp_main(register PerlInterpreter* my_perl) 
{
    my_perl->Iop = Perl_pp_enter(my_perl);
    my_perl->Iop = Perl_pp_nextstate(my_perl);
    my_perl->Iop = Perl_pp_print(my_perl);
    PERL_ASYNC_CHECK;
    /*if (my_perl->Isig_pending) Perl_despatch_signals(my_perl);*/
    my_perl->Iop = Perl_pp_leave(my_perl);
    PERL_ASYNC_CHECK;
    /*if (my_perl->Isig_pending) Perl_despatch_signals(my_perl);*/
    return NULL;
}

int
main(int argc, char **argv, char **env)
{
    PerlInterpreter *my_perl;
    pp_main(aTHX);
}
