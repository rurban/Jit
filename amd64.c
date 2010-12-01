/*
x86_64/amd64 not-threaded, 
PL_op in %rax, &PL_op in %rbx, &PL_sig_pending in %rcx

  55                   	push   %rbp
  48 89 e5             	mov    %rsp,%rbp
  53                    push   %rbx
  51                    push   %rcx
  31 c0			xor    %eax, %eax
  48 89 1d xx xx xx xx  mov    PL_op@GOTPCREL(%rip),%rbx
  48 89 1e xx xx xx xx  mov    PL_sig_pending@GOTPCREL(%rip),%rcx

  e8 xx xx xx xx       	call   Perl_pp_enter@PLT
  48 98                	cltq
  48 89 03 		mov    %rax,(%rbx)

  e8 xx xx xx xx       	call   Perl_pp_nextstate@PLT
  48 98                	cltq
  48 89 03 		mov    %rax,(%rbx)

  48 83 ?? 00          	cmpq   $0x0,(%rcx)
  74 0a                	je     +10 (L2)
  31 c0                	xor    %eax,%eax
  e8 xx xx xx xx        call   Perl_despatch_signals@PLT
  31 c0                	xor    %eax,%eax
L2:
  e8 xx xx xx xx       	call   Perl_pp_print@PLT
  48 98                	cltq
  48 89 03 		mov    %rax,(%rbx)

  e8 xx xx xx xx       	call   Perl_pp_leave@PLT
  48 98                	cltq
  48 89 03 		mov    %rax,(%rbx)

  5?                   	pop    %rcx
  5b                   	pop    %rbx
  c9                   	leaveq 
  c3                   	retq   

Dump of assembler code from 0x1127000 to 0x1127058:
0x0000000001127000:     push   %rbp
0x0000000001127001:     mov    %rsp,%rbp
0x0000000001127004:     sub    $0x8,%rsp
0x0000000001127008:     push   %rbx
0x0000000001127009:     mov    -0x8963b0(%rip),%rbx        # 0x890c60 <PL_op>
0x0000000001127010:     push   %rcx
0x0000000001127011:     mov    -0x8969f3(%rip),%ecx        # 0x890624 <PL_sig_pending>
0x0000000001127017:     callq  0x4ce3f0 <Perl_pp_enter>
0x000000000112701c:     mov    %eax,(%rbx)
0x000000000112701e:     callq  0x4d18a0 <Perl_pp_nextstate>
0x0000000001127023:     mov    %eax,(%rbx)
0x0000000001127025:     callq  0x4d5e20 <Perl_pp_pushmark>
0x000000000112702a:     mov    %eax,(%rbx)
0x000000000112702c:     callq  0x4cb010 <Perl_pp_const>
0x0000000001127031:     mov    %eax,(%rbx)
0x0000000001127033:     callq  0x4da5f0 <Perl_pp_print>
0x0000000001127038:     mov    %eax,(%rbx)
0x000000000112703a:     callq  0x4cfc90 <Perl_pp_leave>
0x000000000112703f:     mov    %eax,(%rbx)
0x0000000001127041:     pop    %rcx
0x0000000001127042:     pop    %rbx
0x0000000001127043:     add    $0x8,%rsp
0x0000000001127047:     leaveq
0x0000000001127048:     retq

*/

T_CHARARR amd64_prolog[] = {
    enter_8
#ifdef HAVE_DISPATCH
    ,push_rcx		/* volatile, but ok for &PL_sig_pending check */
#endif
    /*,push_r12*/ 	/* op->next */
#ifdef HAVE_DISPATCH	/* &PL_sig_pending */
    ,mov_mem_ecx, fourbyte
#endif
};

unsigned char *push_prolog(unsigned char *code) {
    CODE prolog1[] = {
        enter_8,
	push_rbx
#ifdef HAVE_DISPATCH
	,push_rcx
#endif
        /*,push_r12*/};
    PUSHc(prolog1);
#ifdef HAVE_DISPATCH
    T_CHARARR prolog2[] = {
	mov_mem_ecx};
    PUSHc(prolog2);
    PUSHrel(&PL_sig_pending);
#endif
    return code;
}
T_CHARARR amd64_epilog[] = {
    /*pop_r12,*/
#ifdef HAVE_DISPATCH
    pop_rcx,
#endif
    pop_rbx,
    leave,
    ret};

T_CHARARR amd64_call[]  = {
    /*0xb8,0x00,0x00,0x00,0x00,*/ /* mox $0,%eax */
    0xe8}; /* callq PL_op->op_ppaddr@PLT */
T_CHARARR amd64_jmp[]   = {0xff,0x25}; /* jmp *$PL_op->op_ppaddr */
T_CHARARR amd64_save_plop[]  = {
    /*mov_eax_rebx*/    /* fails on amd64 */
    mov_rax_memr	/* mov    %rax,memrel #save new PL_op */
};      
T_CHARARR amd64_nop[]        = {0x90};      /* pad */
T_CHARARR amd64_nop2[]       = {0x90,0x90};      /* jmp pad */
T_CHARARR amd64_dispatch_getsig[] = {
    mov_mem_rcx};
T_CHARARR amd64_dispatch[] = {
    test_ecx_ecx,
    je(5)};

T_CHARARR maybranch_plop[] = {
    /* r12 is not save during function calls, put it onto the local stack */
    mov_mem_rebp8, fourbyte
};
unsigned char *push_maybranch_plop(unsigned char *code, OP* next) {
    CODE maybranch_plop1[] = {
	mov_mem_rebp8};
    PUSHc(maybranch_plop1);
    PUSHrel(&next);
    return code;
}
T_CHARARR maybranch_check[] = {
    cmp_eax_rebp8,
    je_0,fourbyte
};
T_CHARARR maybranch_checkw[] = {
    cmp_eax_rebp8,
    jew_0,fourbyte
};
unsigned char *
push_maybranch_check(unsigned char *code, int fw) {
    CODE maybranch_check[] = {
	cmp_eax_rebp8, 	/* saved prev op->next at -4(%esp) */
	je_0};
    if (abs(fw) > 128) {
        CODE maybranch_checkw[] = {
            cmp_eax_rebp8,
            jew_0};
        PUSHc(maybranch_checkw);
        PUSHrel(fw);
    } else {
        PUSHc(maybranch_check);
        PUSHbyte(fw);
    }
    return code;
}

T_CHARARR gotorel[] = {
    jmpq(0)
};
unsigned char *
push_gotorel(unsigned char *code, U32 label) {
    CODE gotorel[] = {
	jmpq_0};
    PUSHc(gotorel);
    PUSHabs(&label);
    return code;
}

# define PROLOG 	amd64_prolog
# define CALL	 	amd64_call
# define JMP	 	amd64_jmp
# define NOP 	        amd64_nop
# define SAVE_PLOP	amd64_save_plop
# define DISPATCH_GETSIG amd64_dispatch_getsig
# define DISPATCH       amd64_dispatch
# define EPILOG         amd64_epilog
# define MAYBRANCH_PLOP maybranch_plop
# define GOTOREL        gotorel

/*
 * Local variables:
 *   c-basic-offset: 4
 * End:
 * vim: expandtab shiftwidth=4:
 */
