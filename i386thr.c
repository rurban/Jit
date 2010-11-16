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

/* my_perl already on stack, Iop at 4(%ebx) */
T_CHARARR x86thr_prolog[] = { 
    push_ebp,		/* save frame pointer*/
    mov_esp_ebp,	/* set new frame pointer */
    push_edi,                                  
    push_esi,                                  
    push_ebx,		/* &my_perl */     
    push_ecx,                                  
    sub_x_esp(8),       /* room for 2 locals: op, p */
    mov_rebp_ebx(8)     /* mov 0x8(%ebp),%ebx my_perl */
#ifdef HAVE_DISPATCH
    ,mov_mem_4ebp(0)
#endif
};
unsigned char *push_prolog(unsigned char *code) {
    unsigned char prolog[] = {
        push_ebp,		/* save frame pointer*/
        mov_esp_ebp,	/* set new frame pointer */
        push_edi,                                  
        push_esi,                                  
        push_ebx,		/* &my_perl */     
        push_ecx,                                  
        sub_x_esp(8),	     /* room for 2 locals: op, p */
        mov_rebp_ebx(8)    /* mov 0x8(%ebp),%ebx my_perl */
#ifdef HAVE_DISPATCH
        ,mov_mem_4ebp(&PL_sig_pending)
#endif
    };
    PUSHc(prolog);
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

/* call near with my_perl as arg1 */
T_CHARARR x86thr_call[]  = {
    0x89,0x1c,0x24,	/* mov    %ebx,(%esp) */
    0xE8		/* call near offset */
};
/* push my_perl, call near offset $PL_op->op_ppaddr */
T_CHARARR x86thr_save_plop[] = {
    0x89,0x43,0x04	/* mov    %eax,0x4(%ebx) */
}; /* save new PL_op into my_perl */
T_CHARARR x86_nop[]          = {0x90};         /* pad */
T_CHARARR x86thr_dispatch[] = {
    mov_4ebp_edx,	/* value of PL_sig_pending from 4(%ebp) (ptr) to %eax */
    mov_redx_eax,
    test_eax_eax,
    je(8)  		/* je     +8 */
}; /* call   Perl_despatch_signals */

# define PROLOG 	x86thr_prolog
# define CALL	 	x86thr_call
# define JMP	 	x86thr_call
# define SAVE_PLOP	x86thr_save_plop
# define DISPATCH       x86thr_dispatch
# define EPILOG         x86thr_epilog

/*
 * Local variables:
 *   c-basic-offset: 4
 * End:
 * vim: expandtab shiftwidth=4:
 */
