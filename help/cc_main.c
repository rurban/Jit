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
OP *myop;

static OP * pp_main(register PerlInterpreter* my_perl) 
{
    register OP* op;
    register int *p = &PL_sig_pending;
#ifdef DEBUGGING
    debstack();
    debop(myop);
#endif
    my_perl->Iop = Perl_pp_enter(my_perl);
    my_perl->Iop = Perl_pp_nextstate(my_perl);
    my_perl->Iop = Perl_pp_print(my_perl);
    PERL_ASYNC_CHECK;

 maybranch_1:
    op = my_perl->Iop->op_next;
    my_perl->Iop = Perl_pp_cond_expr(my_perl);
    if (*p)
        Perl_despatch_signals(my_perl);
    if (PL_op == op) /* false */
        goto next_1;
 other_1:
    my_perl->Iop = Perl_pp_pushmark(my_perl);
    my_perl->Iop = Perl_pp_const(my_perl);
    my_perl->Iop = Perl_pp_print(my_perl);
    goto leave_1; /* upper scope */

 next_1:
    my_perl->Iop = Perl_pp_enter(my_perl);
    my_perl->Iop = Perl_pp_nextstate(my_perl);
    if (*p)
        Perl_despatch_signals(my_perl);
    my_perl->Iop = Perl_pp_leave(my_perl);
 leave_1:
    my_perl->Iop = Perl_pp_leave(my_perl);

    my_perl->Iop = Perl_pp_leave(my_perl);
    PERL_ASYNC_CHECK;
    return NULL;
}

int
main(int argc, char **argv, char **env)
{
    PerlInterpreter *my_perl;
    myop = newOP(OP_ENTER, 0);
    pp_main(aTHX);
}
