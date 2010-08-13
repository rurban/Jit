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
  0x55,			/* push   %rbp */
  0x48,0x89,0xe5,	/* mov    %rsp, %rbp */
#if (PERL_VERSION > 6) && (PERL_VERSION < 13)
  0x53,			/* push   %rbx */
  0x31,0xdb,            /* xor    %ebx,%ebx */
#endif
};
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
T_CHARARR amd64_epilog[] = {
#if (PERL_VERSION > 6) && (PERL_VERSION < 13)
  0x5b,			/* pop   %rbx */
#endif
  0xc9,   		/* leaveq */
  0xc3};   		/* ret */

# define PROLOG 	amd64_prolog
# define CALL	 	amd64_call
# define JMP	 	amd64_jmp
# define NOP 	        amd64_nop
# define SAVE_PLOP	amd64_save_plop
# define DISPATCH_GETSIG amd64_dispatch_getsig
# define DISPATCH       amd64_dispatch
# define DISPATCH_POST  amd64_dispatch_post
# define EPILOG         amd64_epilog
