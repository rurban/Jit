/*    Jit.xs
 *
 *    Copyright (C) 2010 by Reini Urban
 *
 *    You may distribute under the terms of either the GNU General Public
 *    License or the Artistic License, as specified in the README file.
 *
 *    http://gist.github.com/331867
 */

#include <EXTERN.h>
#include <perl.h>
#include <XSUB.h>

#ifndef _WIN32
#include <sys/mman.h>
#endif

#define T_CHARARR static unsigned char
#define ALIGN_16(c) (c%16?(c+(16-c%16)):c)

/* Call near to a jmp table at the end. gcc uses that.
   The first versions used a simple jmp i.e. call far.
   Need to time this when it works.
*/
/*#define USE_JMP_TABLE*/
#define STACK_SPACE 0x08

/* When do we need PERL_ASYNC_CHECK?
   Until 5.13.2  we had it after each and every op, since 5.13.2 only inside certain ops,
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

/*
C pseudocode

       threaded:
         my_perl->Iop = <PL_op->op_ppaddr>(my_perl);
	 if (my_perl->Isig_pending) Perl_despatch_signals(my_perl);

       not-threaded:
         PL_op = <PL_op->op_ppaddr>();
	 if (PL_sig_pending) Perl_despatch_signals();
*/

#if (defined(__i386__) || defined(_M_IX86)) && defined(USE_ITHREADS)

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
T_CHARARR x86_nop[]          = {0x90};      /* pad */
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
# define NOP 	        x86_nop
# define SAVE_PLOP	x86thr_save_plop
# define DISPATCH_GETSIG x86thr_dispatch_getsig
# define DISPATCH       x86thr_dispatch
# define DISPATCH_POST  x86thr_dispatch_post
# define EPILOG         x86thr_epilog

#endif
#if (defined(__i386__) || defined(_M_IX86)) && !defined(USE_ITHREADS)

/*
x86 not-threaded, PL_op in eax, PL_sig_pending temp in ecx

prolog:
	55                   	pushl   %ebp
	89 e5                	movl    %esp,%ebp
	83 ec 08             	subl    $0x8,%esp    adjust stack space 8
call:
#ifdef USE_JMP_TABLE
	e8 xx xx xx xx		call    pp_? near
#else
	ff 25 xx xx xx xx	jmp     *$PL_op->op_ppaddr ; call far
#endif
save_plop:
        90                      nop
	a3 xx xx xx xx       	mov    %eax,$PL_op  ;0x4061c4

dispatch_getsig:
	8b 0d xx xx xx xx xx	mov    $PL_sig_pending,%ecx
dispatch:
	85 c9                	test   %ecx,%ecx
	74 06                	je     +6
#ifdef USE_JMP_TABLE
	e8 xx xx xx xx		call  Perl_despatch_signals
#else
	ff 25 xx xx xx xx       jmp   *Perl_despatch_signals
#endif
epilog:
	b8 00 00 00 00       	mov    $0x0,%eax
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
T_CHARARR x86_prolog[] = {0x55,			/* push %ebp; */
			  0x89,0xe5,		/* mov %esp, %ebp; */
			/*0x51,*/     		/* push %ecx */
                          0x83,0xec,STACK_SPACE};   /* sub $0x04,%esp */
#endif
#ifdef USE_JMP_TABLE
T_CHARARR x86_call[]  = {0xe8};      /* call near offset */
T_CHARARR x86_jmp[]   = {0xe9};      /* jump32 offset $PL_op->op_ppaddr */
#else
T_CHARARR x86_call[]  = {0xe8};      /* call near offset $PL_op->op_ppaddr */
T_CHARARR x86_jmp[]   = {0xff,0x25}; /* jmp *$PL_op->op_ppaddr */
#endif
T_CHARARR x86_save_plop[]  = {0xa3};      /* save new PL_op */
T_CHARARR x86_nop[]        = {0x90};      /* pad */
T_CHARARR x86_nop2[]       = {0x90,0x90};      /* jmp pad */
T_CHARARR x86_dispatch_getsig[] = {0x8b,0x0d};
#ifdef USE_JMP_TABLE
T_CHARARR x86_dispatch[] = {0x85,0xc9,0x74,0x06,
			    0xE8};
#else
T_CHARARR x86_dispatch[] = {0x85,0xc9,0x74,0x06,
			    0xFF,0x25};
#endif
T_CHARARR x86_dispatch_post[] = {}; /* fails with msvc */
# if 0
T_CHARARR x86_epilog[] = {0x5d,0x8d,0x61,0xfc,   /* restore esp, 8d 61 fc */
			  0xb8,0x00,0x00,0x00,0x00,
			  0xc9,0xc3};
#endif
T_CHARARR x86_epilog[] = {0x89,0xec,          /* mov    %ebp,%esp */
                          0x5d,               /* pop    %ebp */
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
#endif

int dispatch_needed(OP* op);

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
The ASYNC check should be done only when necessary. (TODO)

For now only implemented for x86 with certain hardcoded my_perl offsets.
*/
int
Perl_runops_jit(pTHX)
{
#ifdef dVAR
    dVAR;
#endif
#ifdef DEBUGGING
    register int i;
#endif
    unsigned int rel;
    unsigned char *code, *c;
#ifdef USE_JMP_TABLE
    void **jmp;
    int n = 0;
    int n_jmp = 1;
    int csize;
#endif
#ifndef USE_ITHREADS
    void* PL_op_ptr = &PL_op;
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
        printf("pp_%s \t= 0x%x\n",PL_op_name[PL_op->op_type],PL_op->op_ppaddr);
#endif
	if (PL_op->op_type == OP_NULL) continue;
	size += sizeof(CALL);
#ifdef USE_JMP_TABLE
	n_jmp++; /* number of pp ops */
#endif
	size += sizeof(void*);
#ifndef USE_JMP_TABLE
	while ((size | 0xfffffff0) % 4) {
	    size++;
	}
#endif
	size += sizeof(SAVE_PLOP);
#ifndef USE_ITHREADS
	size += sizeof(void*);
#endif
	if (DISPATCH_NEEDED(PL_op)) {
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
#ifdef USE_JMP_TABLE
    csize = ALIGN_16(size);   /* JMP_TABLE offset */
    size = csize + (n_jmp*8); /* x86 JMP_TABLE size */
#endif
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
#ifdef USE_JMP_TABLE
    /* store local jmp table addresses of pp funcs */
    jmp = (void**)malloc(n_jmp*sizeof(void*));
    jmp[0] = (void*)&Perl_despatch_signals;
    n = 1;
#endif
    PUSHc(PROLOG);
    do {
	if (PL_op->op_type == OP_NULL) continue;
#ifdef USE_JMP_TABLE
	PUSHc(CALL);
        rel = csize-((code+4)-c); /* offset to jmp[0] - despatch */
        /* TODO: linear search in array to reduce code size */
	jmp[n] = (void*)PL_op->op_ppaddr;
        n++;
        rel += n*8;
        PUSHc(&rel);
#else
        rel = (unsigned char*)PL_op->op_ppaddr - (code+1) - 4; /* relative offset to addr */
        if (rel > (unsigned int)1<<31) {
	    PUSHc(JMP);
	    PUSHc(&PL_op->op_ppaddr);
        } else {
	    PUSHc(CALL);
	    PUSHc(&rel);
        }
	/* 386 calls prefer 2 nop's afterwards, align it to 4 (0,4,8,c)*/
	while (((unsigned int)&code | 0xfffffff0) % 4) {
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
#ifdef USE_JMP_TABLE
            rel = csize-((code+4)-c);
	    PUSHc(&rel);
#else
	    PUSHc(&Perl_despatch_signals);
#endif
#ifdef USE_ITHREADS
	    PUSHc(DISPATCH_POST);
#endif
	}
    } while (PL_op = PL_op->op_next);
    PUSHc(EPILOG);

#ifndef USE_JMP_TABLE
# ifdef DEBUGGING
    printf("Perl_despatch_signals \t= 0x%x\n",Perl_despatch_signals);
    printf("PL_sig_pending \t= 0x%x\n",PL_sig_pending);
# endif
#else
    while (((unsigned int)code | 0xfffffff0) % 16) {
        *(code++) = NOP[0];
    }
# ifdef DEBUGGING
    printf("Perl_despatch_signals=0x%x, n_jmp=%d\n",Perl_despatch_signals,n_jmp);
# endif
    for (i=0; i < n_jmp; i++) {
        PUSHc(JMP);
        PUSHc(&jmp[i]);
        PUSHc(x86_nop2);
# ifdef DEBUGGING
        printf("jmp[%d] \t= 0x%x\n",i,jmp[i]);
# endif
    }
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
    printf("PL_op    \t= 0x%x [0x%x]\n",&PL_op,PL_op);
# ifdef USE_JMP_TABLE
    printf("code()=0x%x size=%d, csize=%d",code,size,csize);
# else
    printf("code()=0x%x size=%d",code,size);
# endif
    for (i=0; i < size; i++) {
        if (!(i % 8)) printf("\n");
        printf("%02x ",code[i]);
    }
    printf("\nstart:\n");
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
#if (defined(__i386__) || defined(_M_IX86))
    PL_runops = Perl_runops_jit;
#endif
