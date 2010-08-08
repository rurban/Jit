#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

static OP * pp_main();

#if 0 && PERL_VERSION < 13
#  define PERL_ASYNC_CHECK if (PL_sig_pending) Perl_despatch_signals()
#else
#  define PERL_ASYNC_CHECK
#endif


static OP * pp_main() 
{
    dVAR;
    register OP *op = PL_op;
    PL_op = pp_enter();
    PL_op = pp_nextstate();
    PERL_ASYNC_CHECK;
    PL_op = pp_print();
    PERL_ASYNC_CHECK;
    PL_op = pp_leave();
    PERL_ASYNC_CHECK;
    TAINT_NOT;
    return NULL;
}

int
main(int argc, char **argv, char **env)
{
    pp_main();
}
