/*
       x86 thr: my_perl in ebx, my_perl->Iop in eax and ebx+4
prolog: my_perl passed on stack, but force 16-alignment for stack. core2/opteron just loves that
	8d 4c 24 04          	lea    0x4(%esp),%ecx
	83 e4 f0             	and    $0xfffffff0,%esp
	ff 71 fc             	pushl  -0x4(%ecx)
	55                   	push   %ebp
	89 e5                	mov    %esp,%ebp
	53                   	push   %ebx
        51                   	push   %ecx

call_far:
  	89 1c 24             	mov    %ebx,(%esp)    ; push my_perl
	e8 xx xx xx xx		call   offset to $PL_op->op_ppaddr ; 0x5214a4c5<Perl_pp_enter>
save_plop:
	89 43 04             	mov    %eax,0x4(%ebx) ; save new PL_op into my_perl
PERL_ASYNC_CHECK:
	movl	%ebx, (%esi)	;891e
	movl	%eax, 4(%esi)	;894604
	movl	900(%esi), %eax ;8b8684030000
	testl	%eax, %eax	;85C0
	je	+8   		;7408
	movl	%esi, (%esp)	;893424
	call	_Perl_despatch_signals ;FF25xxxxxxxx

after calling Perl_despatch_signals, restore my_perl into ebx and push for next
	83 c4 10             	add    $0x10,%esp
	83 ec 0c             	sub    $0xc,%esp
	31 db                	xor    %ebx,%ebx
	53                   	push   %ebx

epilog after final Perl_despatch_signals
	83 c4 10             	add    $0x10,%esp
	8d 65 f8             	lea    -0x8(%ebp),%esp
	59                   	pop    %ecx
	5b                   	pop    %ebx
	5d                   	pop    %ebp
	8d 61 fc             	lea    -0x4(%ecx),%esp
	c3                   	ret
*/

/* my_perl already on stack, Iop at 4(%ebx),  */
#define X86THR_PROLOG					\
    push_ebp,		/* save frame pointer*/		\
    mov_esp_ebp,	/* set new frame pointer */ 	\
    push_edi,						\
    push_esi,						\
    push_ebx,		/* &my_perl */			\
    push_ecx,						\
    sub_x_esp(8)	/* room for 2 locals: op, p */ 	\
    /*mov_eax_ebx*/

static unsigned x86thr_prolog[] = { X86THR_PROLOG };
unsigned char *push_prolog(unsigned char *code) {
    PUSHc(x86thr_prolog);
    return code;
}

T_CHARARR x86thr_epilog[] = {
    add_x_esp(8),
    pop_ecx,
    pop_ebx,
    pop_esi,
    pop_edi,
    leave,		/* restore esp, ebp */
    ret
};

/* call near */
T_CHARARR x86thr_call[]  = {
    0x89,0x1c,0x24,	/* mov    %ebx,(%esp) */
    0xE8		/* call near 0xoffset */
};
/* push my_perl, call near offset $PL_op->op_ppaddr */
T_CHARARR x86thr_save_plop[] = {
    0x89,0x43,0x04	/* mov    %eax,0x4(%ebx) */
}; /* save new PL_op into my_perl */
T_CHARARR x86_nop[]          = {0x90};         /* pad */
/* T_CHARARR x86thr_dispatch_getsig[] = {}; */ /* empty decl fails with msvc */
T_CHARARR x86thr_dispatch[] = {
    0x89,0x1e,0x89,0x46,
    0x04,0x8b,0x86,0x84,
    0x03,0x00,0x00,0x85,
    0xC0,0x74,0x08,0x89,
    0x34,0x24,0xFF,0x25
}; /* check and call $Perl_despatch_signals */
/* after calling Perl_despatch_signals, restore my_perl into ebx and push for next.
   restore my_perl into ebx and push */
T_CHARARR x86thr_dispatch_post[] = {
    0x83,0xc4,0x10,0x83,
    0xec,0x0c,0x31,0xdb,
    0x53,0x90
};

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

# define PROLOG 	x86thr_prolog
# define CALL	 	x86thr_call
# define JMP	 	x86thr_call
# define SAVE_PLOP	x86thr_save_plop
# define DISPATCH_GETSIG x86thr_dispatch_getsig
# define DISPATCH       x86thr_dispatch
# define DISPATCH_POST  x86thr_dispatch_post
# define EPILOG         x86thr_epilog

/*
 * Local variables:
 *   c-basic-offset: 4
 * End:
 * vim: expandtab shiftwidth=4:
 */
