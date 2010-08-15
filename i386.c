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
/* Usage: sizeof(PROLOG) + PUSHc(PROLOG) */

T_CHARARR x86_prolog[] = {
    push_ebp,		/* save frame pointer*/
    mov_esp_ebp,	/* set new frame pointer */
    push_ebx,		/* &PL_op  */
    push_ecx,		/* reserve */
    sub_x_esp(8),	/* room for 2 locals: &PL_sig_pending and op */
    mov_mem_rebx(0)    /* &PL_op to ebx */
#ifdef HAVE_DISPATCH
    ,mov_mem_4ebp(0)     /* &PL_sig_pending to -4(%ebp) */
#endif
};

unsigned char * push_prolog(unsigned char *code) {
    unsigned char prolog[] = {
        push_ebp,
        mov_esp_ebp,
        push_ebx,
        push_ecx,
        sub_x_esp(8),
        mov_mem_rebx(&PL_op)
#ifdef HAVE_DISPATCH
	,mov_mem_4ebp(&PL_sig_pending)
#endif
 };
    PUSHc(prolog);
    return code;
}

T_CHARARR x86_epilog[] = {
    add_x_esp(8),
    pop_ecx,
    pop_ebx,
    leave,		/* restore esp */
    ret
};

T_CHARARR x86_call[]  = {0xe8};      	/* call near offset $PL_op->op_ppaddr */
T_CHARARR x86_jmp[]   = {0xff,0x25}; 	/* jmp *$PL_op->op_ppaddr */
T_CHARARR x86_save_plop[]  = {
    mov_eax_8ebp			/* &PL_op in -8(%ebp) */
};
T_CHARARR x86_dispatch_getsig[] = {
    0x8b,0x0d		/* mov $PL_sig_pending,%ecx */
}; /* &PL_sig_pending abs */
T_CHARARR x86_dispatch[] = {
    0x85,0xc9,	/* test   %ecx,%ecx */
    0x74,0x06,  /* je     +6 */
    0xe8};      /* call   Perl_despatch_signals */
/* &Perl_despatch_signals relative */
T_CHARARR x86_dispatch_post[] = {}; /* fails with msvc */

T_CHARARR maybranch_plop[] = {
    mov_mem_rebx(0),
    mov_eax_8ebp
};
unsigned char *
push_maybranch_plop(unsigned char *code) {
  unsigned char maybranch_plop[] = {
    mov_mem_rebx(&PL_op),
    mov_eax_8ebp};
  PUSHc(maybranch_plop);
  return code;
}


# define PROLOG 	x86_prolog
# define EPILOG         x86_epilog
# define CALL	 	x86_call
# define JMP	 	x86_jmp
# define SAVE_PLOP	x86_save_plop
# define DISPATCH_GETSIG x86_dispatch_getsig
# define DISPATCH       x86_dispatch
# define DISPATCH_POST  x86_dispatch_post


