/*
x86_64/amd64 threaded, PL_sig_pending in rcx?
my_perl already on stack, moved to rbx, Iop at 8(%rbx)
per amd64 calling-convention the single pTHX arg (my_perl) 
is in %rdi, not on the stack.

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
    push_rbx,
    mov_rrsp_rbx,       /* my_perl => rbx */
    sub_x_rsp(0x20)
#ifdef HAVE_DISPATCH
    ,push_rcx		/* &sigpending (myperl[xx]) => rcx */
#endif
};
unsigned char *push_prolog(unsigned char *code) {
    PUSHc(amd64thr_prolog);
    return code;
}
T_CHARARR amd64thr_epilog[] = {
    mov_0_rax, /* nullify PL_op */
#ifdef HAVE_DISPATCH
    pop_rcx,
#endif
    add_x_esp(0x20),
    pop_rbx,
    leave,
    ret
};

#define mov_rax_8rbx 	0x48,0x89,0x43,0x08

T_CHARARR amd64thr_call[]  = {
    mov_rbx_rdi,	/* mov    %rbx,%rdi ; my_perl => arg1 */
    call};      	/* callq near offset $PL_op->op_ppaddr */
T_CHARARR amd64thr_jmp[]   = {0xff,0x25}; /* jmp *$PL_op->op_ppaddr */
T_CHARARR amd64thr_save_plop[]  = { /* save new PL_op into my_perl */
    mov_rax_8rbx	/* mov    %rax,0x8(%rbx) */ 
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
bad:
0x0000000000a6c000:     push   %rbp
0x0000000000a6c001:     mov    %rsp,%rbp
0x0000000000a6c004:     push   %rbx
0x0000000000a6c005:     mov    (%rsp),%rbx
0x0000000000a6c009:     sub    $0x20,%rsp
0x0000000000a6c00d:     mov    %rbx,%rdi
0x0000000000a6c010:     callq  0x4e4010 <Perl_pp_enter> ; segv code == my_perl a6c000
0x0000000000a6c015:     mov    %rax,0x8(%rbx)
0x0000000000a6c019:     mov    %rbx,%rdi
0x0000000000a6c01c:     callq  0x4e7330 <Perl_pp_nextstate>
0x0000000000a6c021:     mov    %rax,0x8(%rbx)
0x0000000000a6c025:     mov    %rbx,%rdi
0x0000000000a6c028:     callq  0x4ec510 <Perl_pp_pushmark>
0x0000000000a6c02d:     mov    %rax,0x8(%rbx)
0x0000000000a6c031:     mov    %rbx,%rdi
0x0000000000a6c034:     callq  0x4e1860 <Perl_pp_const>
0x0000000000a6c039:     mov    %rax,0x8(%rbx)
0x0000000000a6c03d:     mov    %rbx,%rdi
0x0000000000a6c040:     callq  0x4f16c0 <Perl_pp_print>
0x0000000000a6c045:     mov    %rax,0x8(%rbx)
0x0000000000a6c049:     mov    %rbx,%rdi
0x0000000000a6c04c:     callq  0x4e55b0 <Perl_pp_leave>
0x0000000000a6c051:     mov    %rax,0x8(%rbx)
0x0000000000a6c055:     mov    $0x0,%eax
0x0000000000a6c05a:     add    $0x20,%rsp
0x0000000000a6c05e:     pop    %rbx
0x0000000000a6c05f:     leaveq
0x0000000000a6c060:     retq

bad:
0x01455000:     push   %rbp
0x01455001:     mov    %rsp,%rbp
0x01455004:     push   %rbx
0x01455005:     sub    $0x20,%rsp
0x01455009:     mov    0x8(%rbp),%ebx
0x0145500c:     mov    %ebx,(%rsp)
0x0145500f:     callq  0x4e4010 <Perl_pp_enter>
0x01455014:     mov    %eax,0x8(%rbx)		: segv
0x01455017:     mov    %ebx,(%rsp)		
0x0145501a:     callq  0x4e7330 <Perl_pp_nextstate>
0x0145501f:     mov    %eax,0x8(%rbx)
0x01455022:     mov    %ebx,(%rsp)
0x01455025:     callq  0x4ec510 <Perl_pp_pushmark>
0x0145502a:     mov    %eax,0x8(%rbx)
0x0145502d:     mov    %ebx,(%rsp)
0x01455030:     callq  0x4e1860 <Perl_pp_const>
0x01455035:     mov    %eax,0x8(%rbx)
0x01455038:     mov    %ebx,(%rsp)
0x0145503b:     callq  0x4f16c0 <Perl_pp_print>
0x01455040:     mov    %eax,0x8(%rbx)
0x01455043:     mov    %ebx,(%rsp)
0x01455046:     callq  0x4e55b0 <Perl_pp_leave>
0x0145504b:     mov    %eax,0x8(%rbx)
0x0145504e:     mov    $0x0,%eax
0x01455053:     pop    %rbx
0x01455054:     add    $0x20,%rsp
0x01455058:     leaveq
0x01455059:     retq
*/

/*
 * Local variables:
 *   c-basic-offset: 4
 * End:
 * vim: expandtab shiftwidth=4:
 */
