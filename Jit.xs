/*    Jit.xs -*- C -*-
 *
 *    Copyright (C) 2010 by Reini Urban
 *    JIT the Perl runloop for x86 32bit, amd64 64bit. More CPU's later.
 *
 *    You may distribute under the terms of either the GNU General Public
 *    License or the Artistic License, as specified in the README file.
 *
 *    http://gist.github.com/331867
 *    http://search.cpan.org/dist/Jit/
 */

#include <EXTERN.h>
#include <perl.h>
#include <XSUB.h>

#ifndef _WIN32
#include <sys/mman.h>
#endif

#define T_CHARARR static unsigned char
#define ALIGN_16(c) (c%16?(c+(16-c%16)):c)

#define STACK_SPACE 0x08   /* private area, not yet used */

int dispatch_needed(OP* op);

/* When do we need PERL_ASYNC_CHECK?
   Until 5.13.2  we had it after each and every op,
   since 5.13.2 only inside certain ops,
   which need to handle pending signals */
#if PERL_VERSION < 13
#define DISPATCH_NEEDED(op) dispatch_needed(op)
#else
#define DISPATCH_NEEDED(op) 0
#endif

#ifdef DEBUGGING
# define DEB_PRINT_LOC(loc) printf(loc" \t= 0x%x\n", loc)
#else
# define DEB_PRINT_LOC(loc)
#endif

#if !(defined(__i386__) || defined(_M_IX86) || defined(__x86_64__) || defined(__amd64))
#error "Only intel supported so far"
#endif
/* __amd64 defines __x86_64 */

/*
C pseudocode of the Perl runloop:

       threaded:
         my_perl->Iop = <PL_op->op_ppaddr>(my_perl);
	 if (my_perl->Isig_pending) Perl_despatch_signals(my_perl);

       not-threaded:
         PL_op = <PL_op->op_ppaddr>();
	 if (PL_sig_pending) Perl_despatch_signals();
*/

#if (defined(__i386__) || defined(_M_IX86))
#define CALL_ALIGN 4

#if defined(USE_ITHREADS)

/*
       x86 thr: my_perl in ebx, my_perl->Iop in eax (ebx+4)
prolog: my_perl passed on stack, but force 16-alignment for stack. core2/opteron just loves that
	8D 4C 24 04 		leal	4(%esp), %ecx
 	83 E4 F0   		andl	$-16, %esp
 	FF 71 FC   		pushl	-4(%ecx)
call_far:
  	89 1c 24             	mov    %ebx,(%esp)    ; push my_perl
	FF 25 xx xx xx xx	jmp    $PL_op->op_ppaddr ; 0x5214a4c5<Perl_pp_enter>
save_plop:
        90                      nop
        90                      nop
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

/* my_perl already on stack, but force 16-alignment for stack  */
T_CHARARR x86thr_prolog[] = {0x8d,0x4c,0x24,0x04,
			     0x83,0xe4,0xf0,0xff,
			     0x71,0xfc};
/* call near not valid */
T_CHARARR x86thr_call[]  = {0x89,0x1c,0x24,0xE8};
			   /* push my_perl, call near offset $PL_op->op_ppaddr */
T_CHARARR x86thr_save_plop[] = {0x90,0x89,0x43,0x04}; /* save new PL_op into my_perl */
T_CHARARR x86_nop[]          = {0x90};         /* pad */
/* T_CHARARR x86thr_dispatch_getsig[] = {}; */ /* empty decl fails with msvc */
T_CHARARR x86thr_dispatch[] = {0x89,0x1e,0x89,0x46,
			       0x04,0x8b,0x86,0x84,
			       0x03,0x00,0x00,0x85,
			       0xC0,0x74,0x08,0x89,
			       0x34,0x24,0xFF,0x25}; /* check and call $Perl_despatch_signals */
/* after calling Perl_despatch_signals, restore my_perl into ebx and push for next.
   restore my_perl into ebx and push */
T_CHARARR x86thr_dispatch_post[] = {0x83,0xc4,0x10,0x83,
				    0xec,0x0c,0x31,0xdb,
				    0x53,0x90};
/* epilog after final Perl_despatch_signals */
T_CHARARR x86thr_epilog[] = {0x83,0xc4,0x10,0x8d,
			     0x65,0xf8,0x59,0x5b,
			     0x5d,0x8d,0x61,0xfc,
			     0xc3,0x90};

# define PROLOG 	x86thr_prolog
# define CALL	 	x86thr_call
# define JMP	 	x86thr_call
# define NOP 	        x86_nop
# define SAVE_PLOP	x86thr_save_plop
# define DISPATCH_GETSIG x86thr_dispatch_getsig
# define DISPATCH       x86thr_dispatch
# define DISPATCH_POST  x86thr_dispatch_post
# define EPILOG         x86thr_epilog

#endif
#if !defined(USE_ITHREADS)

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

#endif /* threads */
#endif /* 386 */

#if (defined(__x86_64__) || defined(__amd64)) 
#define CALL_ALIGN 0

#if !defined(USE_ITHREADS)
/*
amd64 not-threaded, PL_op in rax, PL_sig_pending ?

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
  0x48,0x83,0xec,STACK_SPACE, /* sub $0x8,%rsp */
#if PERL_VERSION < 13
  0x53,			/* push   %rbx */
  0x31,0xdb             /* xor    %ebx,%ebx */
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
#if PERL_VERSION < 13
  0x5b,			/* pop   %rbx */
#endif
  0x89,0xec, 		/* movl    %ebp,%esp */
  0x5d,    		/* popl    %ebp */
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

#endif
#if defined(USE_ITHREADS)
/*
amd64 threaded, PL_op in rax, PL_sig_pending in rbx

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
  0x55,			/* push   %rbp */
  0x48,0x89,0xe5,	/* mov    %rsp, %rbp */
  0x48,0x83,0xec,STACK_SPACE
#if PERL_VERSION < 13
  ,0x53,		/* push   %rbx */
  0x31,0xdb             /* xor    %ebx,%ebx */
#endif
};
T_CHARARR amd64thr_call[]  = {
  0x48,0x89,0xdf,	/* mov    %rbx,%rdi */
  0x48,0x89,0x43,0x08,  /* mov    %rax,0x8(%rbx) */
  0xe8};      		/* callq near offset $PL_op->op_ppaddr */
T_CHARARR amd64thr_jmp[]   = {0xff,0x25}; /* jmp *$PL_op->op_ppaddr */
T_CHARARR amd64thr_save_plop[]  = {
  0x48,0x89,0x05  /* mov %rax,0x5d14ec(%rip) #save new PL_op */
};      
T_CHARARR amd64thr_nop[]        = {0x90};      /* pad */
T_CHARARR amd64thr_nop2[]       = {0x90,0x90};      /* jmp pad */
T_CHARARR amd64thr_dispatch_getsig[] = {0x8b,0x0d};
/*
  74 08                	je     40092c <main+0x38>
  48 89 df             	mov    %rbx,%rdi
  e8 8c fe ff ff       	callq  4007b8 <Perl_despatch_signals@plt>
  31 db                	xor    %ebx,%ebx
*/
T_CHARARR amd64thr_dispatch[] = {0x85,0xc9,0x74,0x06,
				 0xFF,0x25};
T_CHARARR amd64thr_dispatch_post[] = {0x31,0xdb}; /* fails with msvc */
T_CHARARR amd64thr_epilog[] = {0x89,0xec,          /* movl    %ebp,%esp */
			       0x5d,               /* popl    %ebp */
			       0xc3};              /* ret */

# define PROLOG 	amd64thr_prolog
# define CALL	 	amd64thr_call
# define JMP	 	amd64thr_jmp
# define NOP 	        amd64thr_nop
# define SAVE_PLOP	amd64thr_save_plop
# define DISPATCH_GETSIG amd64thr_dispatch_getsig
# define DISPATCH       amd64thr_dispatch
# define DISPATCH_POST  amd64thr_dispatch_post
# define EPILOG         amd64thr_epilog

#endif /* threads */
#endif /* x86_64 */

/**********************************************************************************/

int
dispatch_needed(OP* op) {
  switch (op->op_type) {
   /* sync this list with B::CC CC.pm! */
  case OP_WAIT:
  case OP_WAITPID:
  case OP_NEXTSTATE:
  case OP_AND:
  case OP_COND_EXPR:
  case OP_UNSTACK:
  case OP_OR:
  case OP_DEFINED:
  case OP_SUBST:
    return 1;
  default:
    return 0;
  }
}

/*
Faster jitted execution path without loop,
selected with -MJit or (later) with perl -j.

All ops are unrolled in execution order for the CPU cache,
prefetching is the main advantage of this function.
The ASYNC check is only done when necessary.

For now only implemented for x86 with certain hardcoded
my_perl offsets for threaded perls.
*/
int
Perl_runops_jit(pTHX)
{
#ifdef dVAR
    dVAR;
#endif
#ifdef DEBUGGING
    static int global_loops = 0;
    register int i;
    FILE* fh;
#endif
    unsigned int rel;
    unsigned char *code, *c;
#ifndef USE_ITHREADS
    void* PL_op_ptr = &PL_op;
#endif
#ifdef DEBUGGING
    fh = fopen("run-jit.c", "w+");
    fprintf(fh, "void runops_jit_%d (void);\nvoid runops_jit_%d (void){\n", 
            global_loops, global_loops);
    global_loops++;
#endif

    /* quirky pass 1: need code size to allocate string.
       PL_slab_count should be near the optree size.
       Need to time that against an realloc checker in pass 2.
     */
    OP * root = PL_op;
    int size = 0;
    size += sizeof(PROLOG);
    do {
#ifdef DEBUGGING
        printf("#pp_%s \t= 0x%x\n",PL_op_name[PL_op->op_type],PL_op->op_ppaddr);
#endif
	if (PL_op->op_type == OP_NULL) continue;
	size += sizeof(CALL);
	size += sizeof(void*);
#if CALL_ALIGN
	while ((size | 0xfffffff0) % CALL_ALIGN) { size++; }
#endif
	size += sizeof(SAVE_PLOP);
#ifdef DEBUGGING
# ifdef USE_ITHREADS
        fprintf(fh, "my_perl->Iop = Perl_pp_%s(my_perl);\n", PL_op_name[PL_op->op_type]);
#else
        fprintf(fh, "PL_op = Perl_pp_%s();\n", PL_op_name[PL_op->op_type]);
# endif
#endif
#ifndef USE_ITHREADS
	size += sizeof(void*);
#endif
	if (DISPATCH_NEEDED(PL_op)) {

#ifdef USE_ITHREADS
# ifdef DEBUGGING
            fprintf(fh, "if (my_perl->Isig_pending)\n  Perl_despatch_signals(my_perl);\n");
# endif
#else
# ifdef DEBUGGING
            fprintf(fh, "if (PL_sig_pending)\n  Perl_despatch_signals();\n");
# endif
#endif

#ifndef USE_ITHREADS
	    size += sizeof(DISPATCH_GETSIG);
	    size += sizeof(void*);
#endif
	    size += sizeof(DISPATCH);
	    size += sizeof(void*);
#ifdef USE_ITHREADS
	    size += sizeof(DISPATCH_POST);
#endif
	}
    } while (PL_op = PL_op->op_next);
    size += sizeof(EPILOG);
# ifdef DEBUGGING
    fprintf(fh, "}\n");
    fclose(fh);
    /* for stabs: as run-jit.s; gdb file run-jit.o */
# endif
    PL_op = root;
#ifdef _WIN32
    code = VirtualAlloc(NULL, size,
			MEM_COMMIT | MEM_RESERVE,
			PAGE_EXECUTE_READWRITE);
#else
    code = (char*)malloc(size);
#endif
    c = code;

#define PUSHc(what) memcpy(code,what,sizeof(what)); code += sizeof(what)

    /* pass 2: jit */
    PUSHc(PROLOG);
    do {
	if (PL_op->op_type == OP_NULL) continue;
	/* relative offset to addr */
        rel = (unsigned char*)PL_op->op_ppaddr - (code+1) - sizeof(void*);
        if (rel > (unsigned int)1<<31) {
	    PUSHc(JMP);
	    PUSHc(&PL_op->op_ppaddr);
        } else {
	    PUSHc(CALL);
	    PUSHc(&rel);
        }
	/* 386 calls prefer 2 nop's afterwards, align it to 4 (0,4,8,c)*/
#if CALL_ALIGN
	while (((unsigned int)&code | 0xfffffff0) % CALL_ALIGN) {
	    *(code++) = NOP[0];
	}
#endif
	PUSHc(SAVE_PLOP);
#ifndef USE_ITHREADS
	PUSHc(&PL_op_ptr);
#endif
	if (DISPATCH_NEEDED(PL_op)) {
#ifndef USE_ITHREADS
	    PUSHc(DISPATCH_GETSIG);
	    PUSHc(&PL_sig_pending);
#endif
	    PUSHc(DISPATCH);
	    PUSHc(&Perl_despatch_signals);
#ifdef USE_ITHREADS
	    PUSHc(DISPATCH_POST);
#endif
	}
    } while (PL_op = PL_op->op_next);
    PUSHc(EPILOG);

#ifdef DEBUGGING
    printf("#Perl_despatch_signals \t= 0x%x\n",Perl_despatch_signals);
    printf("#PL_sig_pending \t= 0x%x\n",&PL_sig_pending);
#endif
    /*I_ASSERT(size == (code - c));*/
    /*size = code - c;*/

    PL_op = root;
    code = c;
#ifdef HAS_MPROTECT
    mprotect(code,size,PROT_EXEC|PROT_READ);
#endif
    /* XXX Missing. Prepare for execution: flush CPU cache. Needed on some platforms */

    /* gdb: disassemble code code+200 */
#ifdef DEBUGGING
    printf("#PL_op    \t= 0x%x\n",&PL_op);
    printf("#code()=0x%x size=%d",code,size);
    for (i=0; i < size; i++) {
        if (!(i % 8)) printf("\n#");
        printf("%02x ",code[i]);
    }
    printf("\n#start:\n");
#endif

    (*((void (*)(pTHX))code))(aTHX);

#ifdef _WIN32
    VirtualFree(code, 0, MEM_RELEASE);
#else
    free(code);
#endif
    TAINT_NOT;
    return 0;
}

MODULE=Jit 	PACKAGE=Jit

PROTOTYPES: DISABLE

BOOT:
#if (defined(__i386__) || defined(_M_IX86)) || (defined(__x86_64__) || defined(__amd64))
    PL_runops = Perl_runops_jit;
#endif
