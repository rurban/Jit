/*
x86_64/amd64 not-threaded, 
PL_op in %rax, &PL_op in %rbx, &PL_sig_pending in %rcx

  55                   	push   %rbp
  48 89 e5             	mov    %rsp,%rbp
  53                    push   %rbx
  5?                    push   %rcx
  31 c0			xor    %eax, %eax
  48 89 1d xx xx xx xx  mov    PL_op@GOTPCREL(%rip),%rbx
  48 89 ?? xx xx xx xx  mov    PL_sig_pending@GOTPCREL(%rip),%rcx

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
*/

T_CHARARR amd64_prolog[] = {
  push_rbp,
  mov_rsp_rbp,
  push_r12, /* for register OP* op */
  push_rbx,
  mov_mem_rebx(0)
};
unsigned char *push_prolog(unsigned char *code) {
    unsigned char prolog[] = {
        push_rbp,
        mov_rsp_rbp,
        push_r12,
        push_rbx,
        mov_mem_rebx(&PL_sig_pending),
        mov_mem_4ebp(&PL_op) 
    };
    PUSHc(prolog);
    return code;
}
T_CHARARR amd64_epilog[] = {
  pop_rbx,
  leave,
  ret};

T_CHARARR amd64_call[]  = {0xe8};      /* callq PL_op->op_ppaddr@PLT */
T_CHARARR amd64_jmp[]   = {0xff,0x25}; /* jmp *$PL_op->op_ppaddr */
T_CHARARR amd64_save_plop[]  = {
  0x48,0x98,      /* cltq */
  0x48,0x89,0x05  /* mov %rax,PL_op@REL(%rip) #save new PL_op */
};      
T_CHARARR amd64_nop[]        = {0x90};      /* pad */
T_CHARARR amd64_nop2[]       = {0x90,0x90};      /* jmp pad */
T_CHARARR amd64_dispatch_getsig[] = {0x8b,0x0d};
T_CHARARR amd64_dispatch[] = {0x85,0xc9,0x74,0x06,
			      0xFF,0x25};
T_CHARARR amd64_dispatch_post[] = {}; /* fails with msvc */

T_CHARARR maybranch_plop[] = {
  mov_mem_rebx(0),
  mov_eax_8ebp
};
unsigned char *push_maybranch_plop(unsigned char *code) {
  unsigned char maybranch_plop[] = {
    mov_mem_rebx(&PL_op),
    mov_eax_8ebp
  };
  PUSHc(maybranch_plop);
  return code;
}

# define PROLOG 	amd64_prolog
# define CALL	 	amd64_call
# define JMP	 	amd64_jmp
# define NOP 	        amd64_nop
# define SAVE_PLOP	amd64_save_plop
# define DISPATCH_GETSIG amd64_dispatch_getsig
# define DISPATCH       amd64_dispatch
# define DISPATCH_POST  amd64_dispatch_post
# define EPILOG         amd64_epilog
# define MAYBRANCH_PLOP maybranch_plop
