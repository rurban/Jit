/*
x86_64/amd64 not-threaded, PL_op in rax, PL_sig_pending ?

prolog:
  405164:	55                   	push   %rbp
  405165:	48 89 e5             	mov    %rsp,%rbp
or
  405124:	48 83 ec 08          	sub    $0x8,%rsp
  405128:	e8 2b 1e 01 00       	callq  416f58 <Perl_pp_enter>
  40512d:	48 89 05 ec 14 5d 00 	mov    %rax,0x5d14ec(%rip)        # 9d6620 <PL_op>
  405134:	e8 a5 00 00 00       	callq  4051de <Perl_pp_nextstate>
  405139:	48 89 05 e0 14 5d 00 	mov    %rax,0x5d14e0(%rip)        # 9d6620 <PL_op>
  405140:	e8 dd 7f 00 00       	callq  40d122 <Perl_pp_print>
  405145:	48 89 05 d4 14 5d 00 	mov    %rax,0x5d14d4(%rip)        # 9d6620 <PL_op>
  40514c:	e8 da 28 01 00       	callq  417a2b <Perl_pp_leave>
  405151:	c6 05 19 16 5d 00 00 	movb   $0x0,0x5d1619(%rip)        # 9d6771 <PL_tainted>
  405158:	48 89 05 c1 14 5d 00 	mov    %rax,0x5d14c1(%rip)        # 9d6620 <PL_op>
  40515f:	5a                   	pop    %rdx
  405160:	c3                   	retq   
or
  4051dc:	c9                   	leaveq 
  4051dd:	c3                   	retq   
*/

T_CHARARR amd64_prolog[] = {
  0x55,			/* push   %rbp */
  0x48,0x89,0xe5,	/* mov    %rsp, %rbp */
#if (PERL_VERSION > 6) && (PERL_VERSION < 13)
  0x53,			/* push   %rbx */
  0x31,0xdb,            /* xor    %ebx,%ebx */
#endif
};
T_CHARARR amd64_call[]  = {0xe8};      /* callq near offset $PL_op->op_ppaddr */
T_CHARARR amd64_jmp[]   = {0xff,0x25}; /* jmp *$PL_op->op_ppaddr */
T_CHARARR amd64_save_plop[]  = {
  0x48,0x89,0x05  /* mov %rax,0x5d14ec(%rip) #save new PL_op */
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
