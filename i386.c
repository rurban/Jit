/*
x86 not-threaded, PL_op in eax, PL_sig_pending temp in ecx

prolog:
	55                   	pushl   %ebp
	89 e5                	movl    %esp,%ebp
	83 ec 08             	subl    $0x8,%esp    adjust stack space 8
call:
	e9 xx xx xx xx		jump32  $PL_op->op_ppaddr - code - 3
save_plop:
	a3 xx xx xx xx       	mov    %eax,$PL_op

dispatch_getsig:
	8b 0d xx xx xx xx xx	mov    $PL_sig_pending,%ecx
dispatch:
	85 c9                	test   %ecx,%ecx
	74 06                	je     +6
	ff 25 xx xx xx xx       jmp far *Perl_despatch_signals #absolute
epilog:
	b8 00 00 00 00       	mov    $0x0,%eax 	# clean PL_op
	c9                   	leave
	c3                   	ret
*/

/* stack is already aligned */
#if 0
T_CHARARR x86_prolog[] = {0x8d,0x4c,0x24,0x04, /* stack align 8: lea    0x4(%esp),%ecx */
                          0x83,0xe4,0xf0,      /* and    $0xfffffff0,%esp */
                          0xff,0x71,0xfc,      /* pushl  -0x4(%ecx) */
                          0x55,0x89,0xe5,0x51, /* push %ebp; mov %esp, %ebp; push %ecx */
                          0x83,0xec,STACK_SPACE}; /* sub $0x04,%esp */
#else
T_CHARARR x86_prolog[] = {0x55,			/* pushl %ebp; */
			  0x89,0xe5,		/* movl %esp, %ebp; */
			/*0x51,*/     		/* pushl %ecx */
                          0x83,0xec,STACK_SPACE};   /* sub $0x04,%esp */
#endif
T_CHARARR x86_call[]  = {0xe8};      /* call near offset $PL_op->op_ppaddr */
T_CHARARR x86_jmp[]   = {0xff,0x25}; /* jmp *$PL_op->op_ppaddr */
T_CHARARR x86_save_plop[]  = {0xa3};      /* save new PL_op */
T_CHARARR x86_nop[]        = {0x90};      /* pad */
T_CHARARR x86_nop2[]       = {0x90,0x90};      /* jmp pad */
T_CHARARR x86_dispatch_getsig[] = {0x8b,0x0d};
T_CHARARR x86_dispatch[] = {0x85,0xc9,0x74,0x06,
			    0xFF,0x25};
T_CHARARR x86_dispatch_post[] = {}; /* fails with msvc */
# if 0
T_CHARARR x86_epilog[] = {0x5d,0x8d,0x61,0xfc,   /* restore esp, 8d 61 fc */
			  0xb8,0x00,0x00,0x00,0x00,
			  0xc9,0xc3};
#endif
T_CHARARR x86_epilog[] = {0x89,0xec,          /* movl    %ebp,%esp */
                          0x5d,               /* popl    %ebp */
			  0xc3};              /* ret */

# define PROLOG 	x86_prolog
# define CALL	 	x86_call
# define JMP	 	x86_jmp
# define NOP 	        x86_nop
# define SAVE_PLOP	x86_save_plop
# define DISPATCH_GETSIG x86_dispatch_getsig
# define DISPATCH       x86_dispatch
# define DISPATCH_POST  x86_dispatch_post
# define EPILOG         x86_epilog

