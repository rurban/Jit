/*
x86 not-threaded, PL_op in eax, PL_sig_pending temp in ecx

prolog:
	55                   	push   %ebp
	89 e5                	mov    %esp,%ebp
call:
	e8 xx xx xx xx		call   $PL_op->op_ppaddr - code - 3
save_plop:
	a3 xx xx xx xx       	mov    %eax,$PL_op

dispatch_getsig:
	8b 0d xx xx xx xx	mov    $PL_sig_pending,%ecx
dispatch:
	85 c9                	test   %ecx,%ecx
	74 06                	je     +6
	e8 xx xx xx xx          call   *Perl_despatch_signals #relative
epilog:
	b8 00 00 00 00       	mov    $0x0,%eax 	# clean PL_op
	5d               	pop    %ebp
	c3                   	ret
*/

/* stack is already aligned */
T_CHARARR x86_prolog[] = {
    0x55,		/* push %ebp; 		- save frame pointer*/
    0x89,0xe5,		/* mov  %esp, %ebp; 	- set new frame pointer */
};
T_CHARARR x86_prolog_with_dispatch[] = {
    0x55,		/* push %ebp; */
    0x89,0xe5,		/* mov  %esp, %ebp; */
    0x51,     		/* push %ecx */
};
T_CHARARR x86_call[]  = {0xe8};      	/* call near offset $PL_op->op_ppaddr */
T_CHARARR x86_jmp[]   = {0xff,0x25}; 	/* jmp *$PL_op->op_ppaddr */
T_CHARARR x86_save_plop[]  = {0xa3};    /* mov %eax,$PL_op */
T_CHARARR x86_nop[]        = {0x90};    /* nop */
T_CHARARR x86_dispatch_getsig[] = {
    0x8b,0x0d		/* mov $PL_sig_pending,%ecx */
}; /* &PL_sig_pending abs */
T_CHARARR x86_dispatch[] = {
    0x85,0xc9,	/* test   %ecx,%ecx */
    0x74,0x06,  /* je     +6 */
    0xe8};      /* call   Perl_despatch_signals */
/* &Perl_despatch_signals relative */
T_CHARARR x86_dispatch_post[] = {}; /* fails with msvc */
T_CHARARR x86_epilog[] = {
    /*0x59,*/     	/* pop    %ecx */
    0xc9,               /* leave 	- restore frame pointer */
    0xc3};              /* ret */
T_CHARARR x86_epilog_with_dispatch[] = {
    0x59,     		/* pop    %ecx */
    0xc9,               /* leave */
    0xc3};              /* ret */

#if (PERL_VERSION > 6) && (PERL_VERSION < 13)
# define PROLOG 	x86_prolog_with_dispatch
# define EPILOG         x86_epilog_with_dispatch
#else
# define PROLOG 	x86_prolog
# define EPILOG         x86_epilog
#endif
# define CALL	 	x86_call
# define JMP	 	x86_jmp
# define NOP 	        x86_nop
# define SAVE_PLOP	x86_save_plop
# define DISPATCH_GETSIG x86_dispatch_getsig
# define DISPATCH       x86_dispatch
# define DISPATCH_POST  x86_dispatch_post

