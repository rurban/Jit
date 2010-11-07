/*
x86_64/amd64 threaded, PL_op in rax, PL_sig_pending in rbx

  4008f4:	53                   	push   %rbx
  4008f5:	31 db                	xor    %ebx,%ebx
  4008f7:	48 89 df             	mov    %rbx,%rdi
  4008fa:	e8 f9 fe ff ff       	callq  4007f8 <Perl_pp_enter@plt>
  4008ff:	48 89 df             	mov    %rbx,%rdi
  400902:	48 89 43 08          	mov    %rax,0x8(%rbx)
  400906:	e8 bd fe ff ff       	callq  4007c8 <Perl_pp_nextstate@plt>
  40090b:	48 89 df             	mov    %rbx,%rdi
  40090e:	48 89 43 08          	mov    %rax,0x8(%rbx)
  400912:	e8 c1 fe ff ff       	callq  4007d8 <Perl_pp_print@plt>
  400917:	83 bb 3c 05 00 00 00 	cmpl   $0x0,0x53c(%rbx)
  40091e:	48 89 43 08          	mov    %rax,0x8(%rbx)
  400922:	74 08                	je     40092c <main+0x38>
  400924:	48 89 df             	mov    %rbx,%rdi
  400927:	e8 8c fe ff ff       	callq  4007b8 <Perl_despatch_signals@plt>
  40092c:	31 db                	xor    %ebx,%ebx
  40092e:	48 89 df             	mov    %rbx,%rdi
  400931:	e8 b2 fe ff ff       	callq  4007e8 <Perl_pp_leave@plt>
  400936:	83 bb 3c 05 00 00 00 	cmpl   $0x0,0x53c(%rbx)
  40093d:	48 89 43 08          	mov    %rax,0x8(%rbx)
  400941:	74 08                	je     40094b <main+0x57>
  400943:	48 89 df             	mov    %rbx,%rdi
  400946:	e8 6d fe ff ff       	callq  4007b8 <Perl_despatch_signals@plt>
  40094b:	5b                   	pop    %rbx
  40094c:	c3                   	retq   
*/

T_CHARARR amd64thr_prolog[] = {
    push_rbp,
    mov_rsp_rbp,
    sub_x_rsp(8),
    push_r12
#ifdef HAVE_DISPATCH
    ,push_rbx,
    0x31,0xdb             /* xor    %ebx,%ebx */
#endif
};
unsigned char *push_prolog(unsigned char *code) {
    PUSHc(amd64thr_prolog);
    return code;
}
T_CHARARR amd64thr_epilog[] = {
#ifdef HAVE_DISPATCH
    pop_rbx,
#endif
    pop_r12,
    add_x_esp(8),
    leave,
    ret
};

T_CHARARR amd64thr_call[]  = {
    0x48,0x89,0xdf,	/* mov    %rbx,%rdi */
    0x48,0x89,0x43,0x08,  /* mov    %rax,0x8(%rbx) */
    0xe8};      		/* callq near offset $PL_op->op_ppaddr */
T_CHARARR amd64thr_jmp[]   = {0xff,0x25}; /* jmp *$PL_op->op_ppaddr */
T_CHARARR amd64thr_save_plop[]  = {
    0x48,0x89,0x05  /* mov %rax,0x5d14ec(%rip) #save new PL_op */
};      
T_CHARARR amd64thr_nop2[]       = {0x90,0x90};      /* jmp pad */
T_CHARARR amd64thr_dispatch_getsig[] = {
    0x8b,0x0d};
/*
  74 08                	je     40092c <main+0x38>
  48 89 df             	mov    %rbx,%rdi
  e8 8c fe ff ff       	callq  4007b8 <Perl_despatch_signals@plt>
  31 db                	xor    %ebx,%ebx
*/
T_CHARARR amd64thr_dispatch[] = {
    0x85,0xc9,0x74,0x06,
    0xFF,0x25};
T_CHARARR amd64thr_dispatch_post[] = {0x31,0xdb};

#define mov_rbx_rdi 	0x48,0x89,0xdf
#define mov_rax_8rbx 	0x48,0x89,0x43,0x08
#define mov_rrax_r12	0x4c,0x8b,0x20

T_CHARARR maybranch_plop[] = {
    mov_rbx_rdi,
    mov_rax_8rbx,
    mov_rrax_r12
};
unsigned char *
push_maybranch_plop(unsigned char *code) {
    PUSHc(maybranch_plop);
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

# define PROLOG 	amd64thr_prolog
# define CALL	 	amd64thr_call
# define JMP	 	amd64thr_jmp
# define SAVE_PLOP	amd64thr_save_plop
# define DISPATCH_GETSIG amd64thr_dispatch_getsig
# define DISPATCH       amd64thr_dispatch
# define DISPATCH_POST  amd64thr_dispatch_post
# define EPILOG         amd64thr_epilog
# define MAYBRANCH_PLOP maybranch_plop
# define GOTOREL        gotorel

/*
 * Local variables:
 *   c-basic-offset: 4
 * End:
 * vim: expandtab shiftwidth=4:
 */
