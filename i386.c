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

static unsigned x86_prolog[] = {
    push_ebp,		/* save frame pointer*/
    mov_ebp_esp,	/* set new frame pointer */
    push_ebx,		/* &PL_op */
    push_ecx,	
    sub_x_esp(8),	/* room for 2 locals: $PL_sig_pending and op */
    mov_mem_rebx, 4byte, /* &PL_op */
    mov_mem_4ebp, 4byte  /* &PL_sig_pending */
};

void push_prolog(void) {
    PUSHc(_CA(push_ebp,
              mov_ebp_esp,
              push_ebx,
              push_ecx,
              sub_x_esp(8),
    mov_mem_rebx)); PUSHmov(&PL_op);
    PUSHc(mov_mem_4ebp); PUSHmov(&PL_sig_pending);
}

T_CHARARR x86_epilog[] = {
    add_x_esp(8),
    pop_ecx,
    pop_ebx,
    leave,		/* restore esp */
    ret
}

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

# define PROLOG 	x86_prolog
# define EPILOG         x86_epilog
# define CALL	 	x86_call
# define JMP	 	x86_jmp
# define SAVE_PLOP	x86_save_plop
# define DISPATCH_GETSIG x86_dispatch_getsig
# define DISPATCH       x86_dispatch
# define DISPATCH_POST  x86_dispatch_post

