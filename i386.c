/*
x86 not-threaded, PL_op in ebx, PL_sig_pending temp in 4(%ebp)

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
	74 06                	je     +5
	e8 xx xx xx xx          call   *Perl_despatch_signals #relative

maybranch:
	mov 4(%ebx),%edx	; save op->next




epilog:
	b8 00 00 00 00       	mov    $0x0,%eax 	# clean PL_op
	5d               	pop    %ebp
	c3                   	ret
*/

/* stack is already aligned */
/* Usage: sizeof(PROLOG) + PUSHc(PROLOG) */

T_CHARARR x86_prolog[] = {
    enter_8,
    push_ebx,
    push_edx,
    mov_mem_ebx(0)	/* &PL_op  */
#ifdef HAVE_DISPATCH
    ,mov_mem_4ebp(0)	/* &PL_sig_pending */
#endif
};

unsigned char * push_prolog(unsigned char *code) {
    unsigned char prolog[] = {
        enter_8,
        push_ebx,	/* &PL_op */
        push_edx,	/* needed temp */
        mov_mem_ebx(&PL_op) /* %ebx *IS* preserved across function calls */
#ifdef HAVE_DISPATCH
        ,mov_mem_4ebp(&PL_sig_pending)
#endif
    };
    PUSHc(prolog);
    return code;
}

T_CHARARR x86_epilog[] = {
    pop_edx,
    pop_ebx,
    leave,		/* restore esp */
    ret
};

T_CHARARR x86_call[]  = {0xe8};      	/* call near offset $PL_op->op_ppaddr */
T_CHARARR x86_jmp[]   = {0xff,0x25}; 	/* jmp *$PL_op->op_ppaddr */
T_CHARARR x86_save_plop[]  = {
    mov_eax_rebx			/* &PL_op in %ebx */
};
T_CHARARR x86_dispatch[] = {
    mov_4ebp_edx,	/* value of PL_sig_pending from 4(%ebp) (ptr) to %eax */
    mov_redx_eax,
    test_eax_eax,
    je(5)  		/* je     +5 */
};      		/* call   Perl_despatch_signals */

T_CHARARR maybranch_plop[] = {
    mov_mem_rebp8,fourbyte
};
CODE *
push_maybranch_plop(CODE *code, OP* next) {
    CODE maybranch_plop[] = {
	mov_mem_rebp8};
    PUSHc(maybranch_plop);
    PUSHrel(&next);
    return code;
}
T_CHARARR maybranch_check[] = {
    cmp_eax_rebp8,
    je_0, fourbyte
};
T_CHARARR maybranch_checkw[] = {
    cmp_eax_rebp8,
    jew_0, fourbyte
};

CODE *
push_maybranch_check(CODE *code, int next) {
    CODE maybranch_check[] = {
	cmp_eax_rebp8,
	je_0};
    if (abs(next) > 128) {
        CODE maybranch_checkw[] = {
            cmp_eax_rebp8,
            jew_0};
        PUSHc(maybranch_checkw);
        PUSHrel((CODE*)next);
    } else {
        PUSHc(maybranch_check);
        PUSHbyte(next);
    }
    return code;
}

# define PROLOG 	x86_prolog
# define EPILOG         x86_epilog
# define CALL	 	x86_call
# define JMP	 	x86_jmp
# define SAVE_PLOP	x86_save_plop
# define DISPATCH       x86_dispatch

/*
 * Local variables:
 *   c-basic-offset: 4
 * End:
 * vim: expandtab shiftwidth=4:
 */
