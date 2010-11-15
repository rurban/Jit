/*
x86 not-threaded, PL_op in ebx, PL_sig_pending temp in ecx

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
    push_ebp,		/* save frame pointer */	
    mov_esp_ebp,	/* set new frame pointer */
    push_ebx,		
    push_ecx,		/* temp op->next */
    sub_x_esp(8),
    mov_mem_ebx(0)	/* &PL_op  */
#ifdef HAVE_DISPATCH
    ,mov_mem_4ebp(0)	/* &PL_sig_pending */
#endif
};

unsigned char * push_prolog(unsigned char *code) {
    unsigned char prolog[] = {
        push_ebp,
        mov_esp_ebp,
        push_ebx,	/* &PL_op */
        push_ecx,
        sub_x_esp(8),
        mov_mem_ebx(&PL_op)
#ifdef HAVE_DISPATCH
        ,mov_mem_4ebp(&PL_sig_pending)
#endif
    };
    PUSHc(prolog);
    return code;
}

T_CHARARR x86_epilog[] = {
#ifdef HAVE_DISPATCH
    add_x_esp(8),
#endif
    pop_ecx,
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

/* XXX TODO cmp returned op == op->next => jmp */
T_CHARARR maybranch_plop[] = {
    mov_mem_ecx(0)
    /*mov_eax_8ebp,*/
};
unsigned char *
push_maybranch_plop(unsigned char *code, OP* next) {
    unsigned char maybranch_plop[] = {
	mov_mem_ecx_0};
    PUSHc(maybranch_plop);
    PUSHrel(next);
    return code;
}
T_CHARARR maybranch_check[] = {
    cmp_ecx_eax,
    je(0)
};
unsigned char *
push_maybranch_check(unsigned char *code, int next) {
    unsigned char maybranch_check[] = {
	cmp_ecx_eax,
	je_0};
    if (abs(next) > 128) {
        printf("ERROR: je overflow %d > 128\n", next);
    } else {
        PUSHc(maybranch_check);
        PUSHbyte(next);
    }
    return code;
}

T_CHARARR gotorel[] = {
	jmp(0)
};
unsigned char *
push_gotorel(unsigned char *code, int label) {
    unsigned char gotorel[] = {
	jmp(label)};
    PUSHc(gotorel);
    return code;
}


# define PROLOG 	x86_prolog
# define EPILOG         x86_epilog
# define CALL	 	x86_call
# define JMP	 	x86_jmp
# define SAVE_PLOP	x86_save_plop
# define DISPATCH       x86_dispatch
# define MAYBRANCH_PLOP maybranch_plop
# define GOTOREL        gotorel


/*
 * Local variables:
 *   c-basic-offset: 4
 * End:
 * vim: expandtab shiftwidth=4:
 */
