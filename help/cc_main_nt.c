#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

static OP * pp_main();

#if PERL_VERSION < 13
#  define PERL_ASYNC_CHECK if (PL_sig_pending) Perl_despatch_signals()
#else
#  define PERL_ASYNC_CHECK
#endif


static OP * pp_main() 
{
    register OP* op; 
    register int *plop = &PL_op;
    register int *p = &PL_sig_pending;

    *plop = Perl_pp_enter();
    PL_op = Perl_pp_nextstate();
    *plop = Perl_pp_const();
    PL_op = Perl_pp_padsv();
    PL_op = Perl_pp_sassign();
    PL_op = Perl_pp_nextstate();
    if (*p)
        Perl_despatch_signals();
    PL_op = Perl_pp_padsv();
    PL_op = Perl_pp_const();
    PL_op = Perl_pp_gt();

 maybranch_1:
    op = PL_op->op_next;
    PL_op = Perl_pp_cond_expr();
    if (*p)
        Perl_despatch_signals();
    if (PL_op == op) /* false */
        goto next_1;
 other_1:
    PL_op = Perl_pp_pushmark();
    PL_op = Perl_pp_const();
    PL_op = Perl_pp_print();
    goto leave_1; /* upper scope */

 next_1:
    PL_op = Perl_pp_enter();
    PL_op = Perl_pp_nextstate();
    if (*p)
        Perl_despatch_signals();
    PL_op = Perl_pp_leave();
 leave_1:
    PL_op = Perl_pp_leave();

    TAINT_NOT;
    return NULL;
}

int
main(int argc, char **argv, char **env)
{
    int a = 0;
    pp_main();
    return a;
}
