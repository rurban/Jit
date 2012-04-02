/*    Jit.xs -*- mode:C c-basic-offset:4 -*-
 *
 *    JIT (Just-in-time compile) the Perl5 runloop.
 *    Currently for intel x86 32+64bit. More CPU's later.
 *    Status:
 *      Works only for simple i386 and amd64,
 *      without maybranch ops (return op_other, op_last, ... ignored)
 *
 *    Copyright (C) 2010 by Reini Urban
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
#if defined(DEBUGGING) && defined(__GNUC__)
#include <sys/stat.h>
#endif

/* sync with lib/Jit.pm */
#define HINT_JIT_FLAGS 0x04000000

#if defined(HAVE_LIBDISASM) && defined(DEBUGGING)
#include <libdis.h>
#endif

typedef unsigned char CODE;
#define T_CHARARR static CODE
#undef JIT_CPU
/* if dealing with doubles on sse we want this */
#define ALIGN_16(c) (c%16?(c+(16-c%16)):c) 
#define ALIGN_64(c) (c%64?(c+(64-c%64)):c) 
#define ALIGN_N(n,c) (c%n?(c+(n-c%n)):c) 

HV* otherops = NULL;
HV* otherops1 = NULL;
typedef struct jmptarget {
    OP   *op;       /* the target op */
    char *label;    /* XXX not sure if need this */
    CODE *target;   /* the code points for label (run-time lookup for goto XS and goto label) */
} JMPTGT;
int jmpix = 0;
JMPTGT *jmptargets = NULL;

typedef struct loopstack {
    CODE *nextop;   /* the 3 loop targets */
    CODE *lastop;
    CODE *redoop;
} LOOPTGT;
int loopix = 0;
LOOPTGT *looptargets = NULL;

#define PUSH_JMP(jmp)                                                  \
    jmptargets = (JMPTGT*)realloc(jmptargets, (jmpix+1)*sizeof(JMPTGT)); \
    memcpy(&jmptargets[jmpix], &jmp, sizeof(JMPTGT)); jmpix++
#define POP_JMP 	(jmpix >= 0 ? &jmptargets[jmpix--] : NULL)
#define PUSH_LOOP(cx)                                                  \
    looptargets = (LOOPTGT*)realloc(looptargets, (loopix+1)*sizeof(LOOPTGT)); \
    memcpy(&looptargets[loopix], &cx, sizeof(LOOPTGT)); loopix++
#define POP_LOOP 	(loopix >= 0 ? &looptargets[loopix--] : NULL)

#ifdef DEBUGGING
int global_label;
int global_loops = 0;
int local_chains = 0;
#endif

int dispatch_needed(OP* op);
int maybranch(OP* op);
CODE *push_prolog(CODE *code);
long jit_chain(pTHX_ OP* op, CODE *code, CODE *code_start, 
               int jumpsize, OP* stopop
#ifdef DEBUGGING
              ,FILE *fh, FILE *stabs
#endif
);
/* search dynamically the code target for op in jmptargets */
CODE *jmp_search_label(OP* op);

/* When do we need PERL_ASYNC_CHECK?
 * if (dispatch_needed(op)) if (PL_sig_pending) Perl_despatch_signals();
 *
 * Until 5.13.2 we had it after each and every op,
 * since 5.13.2 only inside certain ops,
 *   which need to handle pending signals.
 * In 5.6 it was a NOOP.
 */
/*#define _BYPASS_DISPATCH*/
#if (PERL_VERSION > 6) && (PERL_VERSION < 13)
#define HAVE_DISPATCH
#define DISPATCH_NEEDED(op) dispatch_needed(op)
#else
#undef HAVE_DISPATCH
#define DISPATCH_NEEDED(op) 0
#endif

#ifdef DEBUGGING
# define JIT_CHAIN_DRYRUN(op) 		  jit_chain(aTHX_ op, NULL, NULL, 0, NULL, fh, stabs)
# define JIT_CHAIN_DRYRUN_FULL(op,stopop) jit_chain(aTHX_ op, NULL, NULL, 0, stopop, fh, stabs)
# define JIT_CHAIN(op) 		   (CODE*)jit_chain(aTHX_ op, code, code_start, 0, NULL, fh, stabs)
# define JIT_CHAIN_FULL(op, size, stopop) \
    (CODE*)jit_chain(aTHX_ op, code, code_start, size, stopop, fh, stabs)
# define DEB_PRINT_LOC(loc) printf(loc" \t= 0x%x\n", loc)
# if PERL_VERSION < 8
#   define DEBUG_v(x) x
# endif
#else
# define JIT_CHAIN_DRYRUN(op) 		   jit_chain(aTHX_ op, NULL, NULL, 0, NULL)
# define JIT_CHAIN_FULL_DRYRUN(op, stopop) jit_chain(aTHX_ op, NULL, NULL, 0, stopop)
# define JIT_CHAIN(op) 		    (CODE*)jit_chain(aTHX_ op, code, code_start, 0, NULL) 
# define JIT_CHAIN_FULL(op, size, stopop) \
    (CODE*)jit_chain(aTHX_ op, code, code_start, size, stopop)
# define DEB_PRINT_LOC(loc)
# if PERL_VERSION < 8
#   define DEBUG_v(x)
# endif
#endif
#define PTR2X(ptr) INT2PTR(unsigned int,ptr)

#ifdef USE_ITHREADS
/* first arg already my_perl, and already on stack */
#  define PUSH_1ARG_DRYRUN  size += sizeof(push_arg2)
#  define PUSH_1ARG  	     PUSHc(push_arg2)
#else
#  define PUSH_1ARG_DRYRUN  size += sizeof(push_arg1)
#  define PUSH_1ARG  	     PUSHc(push_arg1)
#endif

/*
C pseudocode of the Perl runloop:

not-threaded:

  OP *op;
  int *p = &Perl_Isig_pending_ptr;
if maybranch:
  op = PL_op->op_next; 	     # save away at ecx to check
  PL_op = Perl_pp_opname();  # returns op_next, op_other, op_first, op_last 
			     # or a new optree start
  if (dispatch_needed) 
    if (*p) Perl_despatch_signals();

  if (PL_op == op) 	#if maybranch label other targets
    goto next_1;
  # assemble op_other chain until 0
  PL_op = Perl_pp_opname();
  ...
  goto leave_1;
 next_1: #continue with op_next
    ...
 leave_1:
    Perl_pp_leave()
    return

else:

 thisop:
  PL_op = Perl_pp_opname(); #returns op->next
  if dispatch_needed: if (*p) Perl_despatch_signals();
 nextop:


threaded, same logic as above, just:

  my_perl->Iop = PL_op->op_ppaddr(my_perl);
  if (my_perl->Isig_pending) Perl_despatch_signals(my_perl);

*/

#define CALL_SIZE  4				/* size for the call instruction arg */
#define MOV_SIZE   4				/* size for the mov instruction arg */

/* multi without threads yet unhandled. should be a simple s/USE_ITHREADS/MULTIPLICITY/ */
#if defined(MULTIPLICITY) && !defined(USE_ITHREADS)
# error "MULTIPLICITY without ITHREADS not supported"
#endif
#if defined(USE_THREADS) && !defined(USE_ITHREADS)
# error "USE_THREADS without ITHREADS not supported"
#endif
#ifdef USE_ITHREADS
/* threads: offsets are perl version and ptrsize dependent */
# define IOP_OFFSET 		PTRSIZE		/* my_perl->Iop_pending offset */
# define SIG_PENDING_OFFSET 	4*PTRSIZE	/* my_perl->Isig_pending offset */
# define PPADDR_OFFSET          (IOP_OFFSET+2*PTRSIZE)
#else
# define PPADDR_OFFSET          (2*PTRSIZE)
#endif


#define CALL_ABS(abs) 	code = call_abs(code,abs)
/*(U32)((unsigned char*)abs-code-3)*/
#define PUSHc(what) memcpy(code,what,sizeof(what)); code += sizeof(what)
/* force 4 byte for U32, 64bit uses 8 byte for U32, but 4 byte for call near */
#define PUSHcall(what) memcpy(code,&what,CALL_SIZE); code += CALL_SIZE
#define PUSHbyte(byte) { signed char b = (byte); *code++ = b; }

#ifdef DEBUGGING
# define dbg_cline(p1)     fprintf(fh, p1); line++
# define dbg_cline1(p1,p2) fprintf(fh, p1, p2); line++
#else
# define dbg_cline(p1)
# define dbg_cline1(p1,p2)
#endif

#if defined(__GNUC__) && defined(DEBUGGING)
# define dbg_stabs(s)      fprintf(stabs, ".stabn 68,0,%d,%l /* "s" */\n", line, code-code_start)
# define dbg_stabs1(s,p1)  fprintf(stabs, ".stabn 68,0,%d,%l /* "s" */\n", line, code-code_start, p1)
# define dbg_lines(s) 	   dbg_cline(s"\n"); dbg_stabs(s)
# define dbg_lines1(s, p1) dbg_cline1(s"\n", p1); dbg_stabs1(s, p1)
#else
# define dbg_stabs(s)
# define dbg_stabs1(s,p1)
# ifdef DEBUGGING
#  define dbg_lines(s)		dbg_cline(s"\n");
#  define dbg_lines1(s, p1)	dbg_cline1(s"\n", p1); 
# else
#  define dbg_lines(s)
#  define dbg_lines1(s, p1)
# endif
#endif


/* __amd64 defines __x86_64 */
#if defined(__x86_64__) || defined(__amd64) || defined(__amd64__) || defined(_M_X64)
#define JIT_CPU "amd64"
#define JIT_CPU_AMD64
#define CALL_ALIGN 0
#define MOV_REL
#define PUSH_SIZE  4				/* size for the push instruction arg 4/8 */

#define PUSHabs(what) memcpy(code,what,PUSH_SIZE); code += PUSH_SIZE
#define PUSHrel(where) { \
    U32 r = (CODE*)where - (code+MOV_SIZE);	\
    memcpy(code,&r,MOV_SIZE); code += MOV_SIZE; \
}
/*void f_PUSHrel(CODE* code, void *where);*/
/*#define PUSHrel(where) f_PUSHrel(code,(void*)where); code += MOV_SIZE;*/
#define revword(m)	(((unsigned long)m)&0xff),((((unsigned long)m)&0xff00)>>8), \
        ((((unsigned long)m)&0xff0000)>>16),((((unsigned long)m)&0xff000000)>>24), \
        ((((unsigned long)m)&0xff00000000)>>32),((((unsigned long)m)&0xff00000000)>>40), \
        ((((unsigned long)m)&0xff0000000000)>>48),((((unsigned long)m)&0xff0000000000)>>56)
#define revword4(m)	(((unsigned int)m)&0xff),((((unsigned int)m)&0xff00)>>8), \
        ((((unsigned int)m)&0xff0000)>>16),((((unsigned int)m)&0xff000000)>>24)

T_CHARARR NOP[]      = {0x90};    /* nop */

/* PROLOG */
#define enter           0xc8
#define enter_8         0xc8,0x08,0x00,0x00
#define push_rcx	0x51
#define push_rbx 	0x53
#define push_rbp    	0x55
#define mov_rsp_rbp 	0x48,0x89,0xe5
#define push_r12 	0x41,0x54
#define mov_rax_rbx     0x48,0x89,0xc3
#define sub_x_rsp(byte) 0x48,0x83,0xec,byte
#define add_x_esp(byte) 0x48,0x83,0xc4,byte
#define fourbyte        0x00,0x00,0x00,0x00
#define mov_mem_eax(m)	0xa1,revword(m)
/* mov    $memabs,(%ebx) &PL_op in ebx */
#define mov_mem_rbx     0x48,0x8b,0x1d /* mov &PL_op,%rbx */
#define mov_rebp_ebx(byte) 0x8b,0x5d,byte  /* mov 0x8(%ebp),%ebx*/
#define mov_rrsp_rbx    0x48,0x8b,0x1c,0x24    /* mov    (%rsp),%rbx ; my_perl from stack to rbx */

#define mov_mem_rcx     0x48,0x8b,0x0d /* mov &PL_sig_pending,%rcx */
#define test_rcx_rcx	0x48,0x85,0xc9
#define test_ecx_ecx	0x85,0xc9

#define push_imm_0	0x68
#define push_imm(m)	0x68,revword(m)
/* gcc __fastcall amd64 convention for param 1-2 passing */
#define mov_mem_esi     0xbe		/* arg2 */
#define mov_mem_edi     0xbf		/* arg1 */
#define mov_mem_ecx	0xb9      	/* arg1 */
#define mov_eax_edi     0x89,0xc7
#define mov_eax_esi     0x89,0xc6
#define mov_eax_ecx     0x89,0xc1
#define mov_eax_edx     0x89,0xc2
#define mov_rax_rdi     0x48,0x89,0xc7
#define mov_rax_rsi     0x48,0x89,0xc6
#define mov_rax_rcx     0x48,0x89,0xc1
#define mov_rax_rdx     0x48,0x89,0xc2

#ifndef _WIN64
#define push_arg1_mem   mov_mem_edi	/* if call via register */
#define push_arg2_mem   mov_mem_esi
#define push_arg1_eax   mov_rax_rdi
#define push_arg2_eax   mov_rax_rsi
#else
/* Win64 Visual C __fastcall uses rcx,rdx for the first int args, not rdi,rsi
   We use less than 2GB for our vars and subs.
 */
#define mov_mem_edx     0xba		/* arg2 */
#define push_arg1_mem   mov_mem_ecx	/* if call via register */
#define push_arg2_mem   mov_mem_edx
#define push_arg1_eax   mov_rax_rcx
#define push_arg2_eax   mov_rax_rdx
#endif

#ifndef _WIN64
#define mov_rbx_arg1   0x48,0x89,0xdf /* my_perl => arg1 in rdi */
#else
#define mov_rbx_arg1   0x48,0x89,0xdf /* my_perl => arg1 in rcx */
#endif
#define mov_rebx_mem    0x48,0x89,0x1d /* movq (%ebx), &PL_op */
#define mov_mem_rebx	0x48,0xc7,0x03 /* movq &PL_op, (%ebx) */
#define mov_eax_rebx	0x89,0x03      /* movq %rax,(%rbx) &PL_op in ebx */
/* &PL_op in -4(%ebp) */
/* #define mov_mem_4ebp	0xc7,0x45,0xfc */

/* EPILOG */
#define pop_rcx 	0x59
#define pop_rbx 	0x5b
#define pop_r12    	0x41,0x5c
#define leave 		0xc9
#define ret 		0xc3

/* maybranch: */
/* &op in -8(%ebp) */
#define mov_eax_8ebp 	0x89,0x45,0xf8
#define cltq 		0x48,0x98
#define mov_0_rax	0xb8,0x00,0x00,0x00,0x00

#define call 		0xe8	    /* + 4 rel */
#define ljmp(abs) 	0xff,0x25   /* + 4 memabs */

#define mov_mem_rrsp    0xc7,0x04,0x24	/* store op->next on stack */
#define mov_eax_4ebp 	0x89,0x45,0xfc
#define mov_mem_r12	0x41,0xbc 	/* movq PL_op->next, %r12 */
#define cmp_rax_r12     0x49,0x39,0xc4

#define je_0        	0x74
#define je(byte)        0x74,(byte)
#define jew_0        	0x0f,0x84
#define jew(word)       0x0f,0x84,revword4(word)
#define jmpq_0   	0xe9        /* maybranch */
#define jmpq(word)   	0xe9,revword(word)

/* mov    %rax,(%rbx) &PL_op in ebx */
#define mov_rax_memr    0x48,0x89,0x05 /* + 4 rel */
#define mov_eax_rebx    0x89,0x03
#define mov_4ebp_edx    0x8b,0x55,0xfc
#define mov_reax_ebx    0x48,0x8b,0x18
#define mov_redx_eax    0x82,0x02
#define test_eax_eax    0x85,0xc0
/* skip call	_Perl_despatch_signals */
#define mov_mem_rebp8   0xc7,0x45,0xf8  	/* mov &op,-8(%rbp) */
#define cmp_eax_rebp8   0x39,0x45,0xf8  	/* cmp %eax,-8(%rbp) */
#if 0
#define mov_mem_resp1	0xc7,0x44,0x24,0x0fc
#define cmp_eax_resp1   0x39,0x44,0x24,0xfc /* 4 byte cmp %eax,4(%rsp) */
#endif
/*#define cmp_rax_rrsp    0x48,0x39,0xe0 *//* 8 byte */
/*#define test_rax_rax    0x48,0x85,0xc0*/

#ifdef USE_ITHREADS
# include "amd64thr.c"
#else
# include "amd64.c"
#endif

#endif /* EOF amd64 */

#if !defined(JIT_CPU) && (defined(__i386__) || defined(__i386) || defined(_M_IX86))
#define JIT_CPU "i386"
#define JIT_CPU_X86
#define CALL_ALIGN 4
#undef  MOV_REL
#define PUSH_SIZE  4				/* size for the push instruction arg 4/8 */

#define PUSHabs(what) memcpy(code,what,PUSH_SIZE); code += PUSH_SIZE
#define PUSHrel(what) memcpy(code,what,MOV_SIZE);  code += MOV_SIZE
#define revword(m)	(((unsigned int)m)&0xff),((((unsigned int)m)&0xff00)>>8), \
        ((((unsigned int)m)&0xff0000)>>16),((((unsigned int)m)&0xff000000)>>24)
#define absword(m)	((((unsigned int)m)&0xff000000)>>24), \
        ((((unsigned int)m)&0xff0000)>>16),((((unsigned int)m)&0xff00)>>8),(((unsigned int)m)&0xff)

T_CHARARR NOP[]      = {0x90};    /* nop */
#define fourbyte        0x00,0x00,0x00,0x00

/* PROLOG */
#define enter_8         0xc8,0x08,0x00,0x00
#define push_ebx 	0x53
#define push_ebp    	0x55
#define mov_esp_ebp 	0x89,0xe5
#define push_edi 	0x57
#define push_esi	0x56
#define push_ecx	0x51
#define push_edx	0x52
#define sub_x_esp(byte) 0x83,0xec,byte
#define mov_eax_rebx	0x89,0x03	/* mov    %rax,(%rbx) &PL_op in ebx */

#define push_imm_0	0x68
#define push_imm(m)	0x68,revword(m)
#define push_eax 	0x50
#define push_arg1_eax   push_eax
#define push_arg2_eax   push_eax
#define push_arg1_mem   push_imm_0
#define push_arg2_mem   push_imm_0

/* mov    $memabs,%eax PL_op in eax */
#define mov_mem_eax(m)	0xa1,revword(m)
/* mov    $memabs,%ebx &PL_op in ebx */
#define mov_mem_ebx(m)	0xbb,revword(m)
/* mov    $memabs,0(%esp) &PL_op to stack-0 */
#define mov_mem_ecx	0xb9
/* &PL_sig_pending in -4(%ebp) */
#define mov_mem_4ebp(m)	0xc7,0x45,0xfc,revword(m)
#define mov_4ebp_edx	0x8b,0x55,0xfc
#define mov_redx_eax	0x8b,0x02
#define test_eax_eax    0x85,0xc0
#define je_0        	0x74
#define je(byte) 	0x74,(byte)

#define mov_mem_rebp8   0xc7,0x45,0xf8  	/* mov &op,-8(%rbp) */
#define cmp_eax_rebp8   0x39,0x45,0xf8  	/* cmp %eax,,-8(%rbp) */
#if 0
#define mov_mem_resp1	0xc7,0x44,0x24,0xfc
#define cmp_eax_resp1   0x39,0x44,0x24,0xfc /* 4 byte cmp %eax,4(%rsp) */
#endif
#define cmp_ecx_eax     0x39,0xc8
#define mov_rebp_ebx(byte) 0x8b,0x5d,byte  /* mov 0x8(%ebp),%ebx*/
#define test_eax_eax    0x85,0xc0

/* XXX on i386 also? */
#define jew_0        	0x0f,0x84
#define jew(word)       0x0f,0x84,revword4(word)


/* EPILOG */
#define add_x_esp(byte) 0x83,0xc4,byte	/* add    $0x4,%esp */
#define pop_ecx    	0x59
#define pop_ebx 	0x5b
#define pop_edx 	0x5a
#define pop_esi 	0x5e
#define pop_edi 	0x5f
#define pop_ebp 	0x5d
#define leave 		0xc9
#define ret 		0xc3

/* maybranch: */
/* &op in -8(%ebp) */
#define mov_eax_8ebp 	0x89,0x45,0xf8
#define mov_eax_4ebp 	0x89,0x45,0xfc

#define call 		0xe8	    /* + 4 rel */
#define ljmp(abs) 	0xff,0x25   /* + 4 memabs */
#define ljmp_0 		0xff,0x25   /* + 4 memabs */
#define mov_eax_mem 	0xa3	    /* + 4 memabs */
#define jmpb_0   	0xeb        /* maybranch */
#define jmpb(byte)   	0xeb,(byte) /* maybranch */
#define jmpq_0   	0xe9        /* maybranch */
#define jmpq(word)   	0xe9,revword(word)

#ifdef USE_ITHREADS
# include "i386thr.c"
#else
# include "i386.c"
#endif

/* save op = op->next 
   XXX TODO %ecx is not preserved between function calls. Need to use the stack.
*/
T_CHARARR gotorel[] = {
    jmpq(0)
};
CODE *
push_gotorel(CODE *code, int label) {
    CODE gotorel[] = {
	jmpq_0};
    PUSHc(gotorel);
    PUSHabs(&label);
    return code;
}

# define MAYBRANCH_PLOP maybranch_plop
# define GOTOREL        gotorel

#endif /* EOF i386 */

#if defined(JIT_CPU_X86) || defined(JIT_CPU_AMD64)

int
sizeof_maybranch_check(int fw) {
    if (abs(fw) > 128) {
        return sizeof(maybranch_checkw);
    } else {
        return sizeof(maybranch_check);
    }
}

T_CHARARR ifop0return[] = {
    test_eax_eax,
    je(sizeof(EPILOG))
};
T_CHARARR ifop0goto[] = {
    test_eax_eax,
    je_0, fourbyte
};
T_CHARARR ifop0gotow[] = {
    test_eax_eax,
    jew_0, fourbyte
};
CODE *
push_ifop0goto(CODE *code, int next) {
    CODE ifop0goto[] = {
        test_eax_eax,
	je_0};
    if (abs(next) > 128) {
        CODE ifop0gotow[] = {
            test_eax_eax,
            jew_0};
        PUSHc(ifop0gotow);
        PUSHrel((CODE*)next);
    } else {
        PUSHc(ifop0goto);
        PUSHbyte(next);
    }
    return code;
}

T_CHARARR add_eax_ppaddr[] = {
    0x83,0xc0,PPADDR_OFFSET /* add $8,%eax */
};
T_CHARARR call_eax[] = {
    0xff,0xd0 /* call   *%eax */
};
#endif

#if defined(__ia64__) || defined(__ia64) || defined(_M_IA64)
#error "IA64 not supported so far"
#endif
#if defined(__sparcv9)
#error "SPARC V9 not supported so far"
#endif
#if defined(__arm__)
#error "ARM or THUMB not supported so far"
#endif

#ifndef JIT_CPU
#error "Only intel x86_32 and x86_64/amd64 supported so far"
#endif

#ifndef PUSHrel
# ifdef MOV_REL /* amd64 */
#  define PUSHrel(where) { \
    U32 r = (CODE*)where - (code+4); \
    memcpy(code,&r,MOV_SIZE); code += MOV_SIZE; \
}
# else
#  define PUSHrel(what) memcpy(code,what,MOV_SIZE); code += MOV_SIZE
# endif
#endif

/**********************************************************************************/

#ifdef PROFILING
#define NV_1E6 1000000.0
#ifdef WIN32
# include <time.h>
#else
# include <sys/time.h>
#endif
NV
mytime() {
    struct timeval Tp;
    struct timezone Tz;
    int status;
    status = gettimeofday (&Tp, &Tz);
    if (status == 0) {
        Tp.tv_sec += Tz.tz_minuteswest * 60;	/* adjust for TZ */
        return Tp.tv_sec + (Tp.tv_usec / NV_1E6);
    } else {
        return -1.0;
    }
}
#endif

int
dispatch_needed(OP* op) {
#ifdef BYPASS_DISPATCH
    return 0; 			/* for TESTING only */
#endif
    switch (op->op_type) {	/* sync this list with B::CC */
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

int
maybranch(OP* op) {
#ifdef BYPASS_MAYBRANCH
    return 0; 			/* for TESTING only */
#endif
    switch (op->op_type) { 	/* XXX sync this list with Opcodes.pm */
    case OP_SUBSTCONT:		/* LOGOP other or next */
    case OP_GREPWHILE:		/* LOGOP other or next */
    case OP_MAPWHILE:		/* LOGOP other or next */
    case OP_AND:		/* LOGOP other or next */
    case OP_OR:			/* LOGOP other or next */
    case OP_COND_EXPR:		/* LOGOP other or next */
    case OP_ANDASSIGN:		/* LOGOP other or next */
    case OP_ORASSIGN:		/* LOGOP other or next */
#if PERL_VERSION > 8
    case OP_DOR:		/* LOGOP other or next */
    case OP_DORASSIGN:		/* LOGOP other or next */
    case OP_ENTERWHEN:		/* LOGOP other or next */
    case OP_ENTERGIVEN:		/* LOGOP other or next */
    case OP_ONCE:		/* LOGOP other or next */
#endif
    case OP_RANGE:		/* LOGOP other or next */
    /* static */
    case OP_FLIP:		/* first->other or next. not tested */
    case OP_SUBST:		/* pmreplroot or other or next. nyi */
    case OP_ENTERSUB:           /* CvSTART(cv)|autoload or next */
    case OP_DUMP: 		/* main_start. XXX makes no sense to support */
    case OP_FORMLINE:		/* initially only: doparseform */
    case OP_GREPSTART:		/* next->next or next->other */
    /* contexts */    
    case OP_ENTERLOOP:		/* LOOPOP cx->redoop|lastop|nextop */
    case OP_ENTERITER:		/* LOOPOP cx->redoop|lastop|nextop */
    case OP_LAST:		/* LOOPOP cx->lastop->next or cx->blk_sub|eval|format.retop */
    case OP_NEXT:		/* LOOPOP cx->nextop */
    case OP_REDO:		/* LOOPOP cx->redoop but if enter, enter->next */
    case OP_RETURN:		/* cx->blk_sub|eval|format.retop */
    case OP_DBSTATE:
    case OP_REQUIRE: 		/* ? */
    case OP_ENTEREVAL:		/* cx->blk_eval.retop */
    case OP_ENTERTRY:		/* cx->blk_eval.retop */
    case OP_GOTO:		/* cx->blk_sub.retop or CvSTART(cv)|autoload or findlabel */
    case OP_LEAVEEVAL: 		/* ? */
#if PERL_VERSION > 8
    case OP_CONTINUE:		/* cx->blk_givwhen.leaveop */
    case OP_BREAK: 		/* ? */
#endif
        return 1;
    default:
        return 0;
    }
}

CODE *
call_abs (CODE *code, void *addr) {
    /* intel specific: */
    register signed long rel = (CODE*)addr - code - sizeof(CALL) - CALL_SIZE;
    if (rel > (unsigned int)PERL_ULONG_MAX) {
	PUSHc(JMP);
	PUSHcall(addr);
	/* 386 far calls prefer 2 nop's afterwards, align it to 4 (0,4,8,c)*/
#if CALL_ALIGN
	while (((unsigned int)&code | 0xfffffff0) % CALL_ALIGN) { *(code++) = NOP[0]; }
#endif
    } else {
	U32 urel = (U32)rel;
	PUSHc(CALL);
	PUSHcall(urel);
    }
    return code;
}

/* Search dynamically (in Jit) the code target for op in jmptargets */
CODE *jmp_search_label(OP* op) {
    int ix = jmpix;
    while (ix-- > 0) {
        if (jmptargets[ix].op == op) { /* no loop */
            return jmptargets[ix].target;
        }
    }
    return (CODE*)0;
}

long
jit_chain(pTHX_
	  OP *op,
	  CODE *code,
	  CODE *code_start,
          int jumpsize,
	  OP *stopop
#ifdef DEBUGGING
	  ,FILE *fh, FILE *stabs
#endif
	  )
{
    int dryrun = !code;
    int size = 0;
    OP *startop = op;
    OP *opnext;
#ifdef DEBUGGING
    static int line = 3;
    char *opname;

    if (!dryrun) {
	opname = (char*)PL_op_name[op->op_type];
        fprintf(fh, "/* block jit_chain_%d op 0x%x pp_%s; */\n", 
		local_chains, PTR2X(op), opname);
        local_chains++;
        line++;
    }
#endif

    do {
        opnext = op->op_next;
#ifdef DEBUGGING
	if (!dryrun) {
	    opname = (char*)PL_op_name[op->op_type];
	    DEBUG_v( printf("# pp_%s \t= 0x%x / 0x%x\n", opname,
			    PTR2X(op->op_ppaddr),
			    PTR2X(op)));
	}
# if defined(DEBUG_s_TEST_)
        if (DEBUG_s_TEST_) {
            if (dryrun) {
                size += sizeof(CALL) + CALL_SIZE;
            } else {
                CALL_ABS(&Perl_debstack);
                dbg_lines("debstack();");
            }
        }
# endif
# if defined(DEBUG_t_TEST_)
        if (DEBUG_t_TEST_ && op) {
            T_CHARARR push_arg1[] = { push_arg1_mem };
#  ifdef USE_ITHREADS
            T_CHARARR push_arg2[] = { push_arg2_mem };
#  endif
            if (dryrun) {
		PUSH_1ARG_DRYRUN;
                size += PUSH_SIZE + sizeof(CALL) + CALL_SIZE;
            } else {
		PUSH_1ARG;
                PUSHabs(op);
                CALL_ABS(&Perl_debop);
                DEBUG_v( printf("# debop(%x) %s\n", PTR2X(op),
				(char*)PL_op_name[op->op_type]));
                dbg_lines("debop(PL_op);");
            }
        }
# endif
#endif

	if (op->op_type == OP_NULL) continue;

        /* check labels -> store possible jmp targets. 
           Note: nextstate can also be normal jmp target as enter */
	if (!dryrun) {
            if ((op->op_type == OP_NEXTSTATE)|(op->op_type == OP_DBSTATE)) {
                char *label = NULL;
                JMPTGT cx;
#ifdef CopLABEL
                label = (char *)CopLABEL(cCOPx(op));
#else
                label = cCOPx(op)->cop_label;
#endif
		if (*label) {
                    cx.op = op;
                    cx.label = label;
                    cx.target = code;
                    DEBUG_v( printf("#  push jmp label %s at 0x%x for nextstate 0x%x\n", label, 
				    PTR2X(code), PTR2X(op)));
                    PUSH_JMP(cx);
                } else {
                    cx.op = op;
                    cx.label = NULL;
                    cx.target = code;
                    DEBUG_v( printf("#  push jmp at 0x%x for nextstate op=0x%x\n", 
				    PTR2X(code - code_start), PTR2X(op)));
                    PUSH_JMP(cx);
                }
                if (op->op_type == OP_ENTER) {
                    JMPTGT cx;
                    cx.op = op;
                    cx.label = NULL;
                    cx.target = code;
                    DEBUG_v( printf("#  push jmp at 0x%x for enter op=0x%x\n",
				    PTR2X(code - code_start), PTR2X(op)));
                    PUSH_JMP(cx);
                }
            }
        }

        /* XXX TODO
         * We have almost no chance to get the CvSTART of the sub here, better in the parser.
         * But we can try checking a CvSTART:
         * - On XS functions the CvSTART is added dynamically at run-time,
         *   but it makes no sense to jit already compiled XS code. Good.
         * - autoloaded non-xs code would be good to jit, but we'd need 
         *   a run-time check for the CvSTART, and Jit it at run-time.
         * For now we can only call unjitted functions.
         * We'd have to call entersub, but then we'd need the prev. 
         * context (name in the prev gv),
         *  ... and we cannot call the chain at compile-time.
         */
	if (0 && (op->op_type == OP_ENTERSUB)) {
            SV *sv; /* arg from the previous GV */
            CV* cv;
            /* first jit the sub, then loop through it.
               loop CvROOT until !PL_op */
            /*OP* next = Perl_pp_entersub(aTHX); / * find CvSTART */
            UNOP* next = cUNOPx(op)->op_first;
            if (next) {
                next = (UNOP*)(next->op_next);
                if (dryrun) {
                    size += JIT_CHAIN_FULL_DRYRUN((OP*)next, opnext);
                } else {
                    int lsize;
                    DEBUG_v( printf("#  entersub() => op=0x%x\n", PTR2X(next)));
                    dbg_lines1("sub_%d: {", global_label);
                    lsize = JIT_CHAIN_FULL_DRYRUN((OP*)next, opnext);
                    code  = JIT_CHAIN_FULL((OP*)next, lsize, opnext);
                    dbg_lines("}");
                    dbg_lines1("next_%d:", global_label);
                }
            }
        }
	
        if (maybranch(op)) {
	    if (dryrun) {
		size += sizeof(maybranch_plop);
	    } else {
                /* store op->next at 0(%esp). Later cmp returned op == op->next => jmp */
                DEBUG_v( printf("# maybranch %s 0x%x:\n", opname, op->op_ppaddr));
                dbg_lines("op = PL_op->op_next;");
		code = push_maybranch_plop(code, opnext);
	    }
        }
	if (dryrun) {
	    size += sizeof(CALL) + CALL_SIZE;
	} else {
#ifdef USE_ITHREADS
	    dbg_cline1("my_perl->Iop = Perl_pp_%s(my_perl);\n", opname);
#else
            dbg_cline1("PL_op = Perl_pp_%s();\n", opname);
#endif
            dbg_stabs1("call pp_%s", opname);
	    CALL_ABS(op->op_ppaddr);
            dbg_stabs("PL_op = eax");
	}
	if (dryrun) {
	    size += sizeof(SAVE_PLOP);
#if defined(JIT_CPU_AMD64) && !defined(USE_ITHREADS)
            size += MOV_SIZE;
#endif
	} else {
	    PUSHc(SAVE_PLOP);
#if defined(JIT_CPU_AMD64) && !defined(USE_ITHREADS)
	    PUSHrel(&PL_op);
#endif
	}

#ifdef HAVE_DISPATCH
	if (DISPATCH_NEEDED(op)) {
	    if (!dryrun) {
# ifdef USE_ITHREADS
		dbg_lines("if (my_perl->Isig_pending)");
                dbg_lines("  Perl_despatch_signals(my_perl);");
# else
		dbg_lines("if (PL_sig_pending)");
		dbg_lines("  Perl_despatch_signals();");
# endif
	    }
# ifdef DISPATCH_GETSIG
	    if (dryrun) {
		size += sizeof(DISPATCH_GETSIG);
		size += MOV_SIZE;
	    } else {
		PUSHc(DISPATCH_GETSIG);
		PUSHrel(&PL_sig_pending);
	    }
# endif
	    if (dryrun) {
		size += sizeof(DISPATCH) + sizeof(CALL) + CALL_SIZE;
	    } else {
		PUSHc(DISPATCH);
		CALL_ABS(&Perl_despatch_signals);
	    }
        }
#endif

        /* other before next */
	if (maybranch(op)) {
            int lsize;
            SV *keysv = newSViv(PTR2IV(op));
            /* XXX avoid cyclic loops of already jitted other ops:
               and => nextstate, cond_expr => enter, ... */
            if (!otherops)  {
                otherops = newHV();
                otherops1 = newHV();
            }
	    if (dryrun) {
                if (hv_exists_ent(otherops1, keysv, 0)) {
                    goto NEXT;
                } else {
                    hv_store_ent(otherops1, keysv, newSViv((int)code), 0);
                }
            } else {
                if (hv_exists_ent(otherops, keysv, 0)) {
                    DEBUG_v( printf("# %s 0x%x already jitted, code=0x%x\n", PL_op_name[op->op_type],
                                    PTR2X(op), PTR2X(code)));
                    /* XXX when is a jmp to this op needed? patch later or use the code addr from the hash */
                    goto NEXT;
                } else {
                    hv_store_ent(otherops, keysv, newSViv((int)code), 0);
                }
		/* dbg_lines1("if (PL_op == op) goto next_%d;", global_label); */
	    }
	    if (((PL_opargs[op->op_type] & OA_CLASS_MASK) == OA_LOGOP) 
                && (op->op_type != OP_ENTERTRY))
            {
                if (dryrun) {
                    int i = JIT_CHAIN_DRYRUN(cLOGOPx(op)->op_other);
                    size += i + sizeof_maybranch_check(i);
                    size += sizeof(GOTOREL);
                } else {
                    int next, other;
                    LOGOP* logop;
                    logop = cLOGOPx(op);
                    DEBUG_v( printf("# other_%d: %s => %s, ", global_label,
                                    PL_op_name[op->op_type],
                                    PL_op_name[cLOGOPx(op)->op_other->op_type]));
                    other = JIT_CHAIN_DRYRUN(logop->op_other); /* sizeof other */
                    other += sizeof(GOTOREL);
                    code = push_maybranch_check(code, other); /* if cmp: je => next */
                    dbg_lines1("if (PL_op != op) goto next_%d;", global_label);
                    DEBUG_v( printf("size=%x\n", PTR2X(other)) );
                    code = JIT_CHAIN(logop->op_other);
                    dbg_cline1("/*goto logop_%d;*/", global_label);
                    dbg_lines1("next_%d:", global_label);
                    next = JIT_CHAIN_DRYRUN(logop->op_next);  /* sizeof next */
                    DEBUG_v( printf("# next_%d: %s, size=%x\n", global_label, 
                                    PL_op_name[logop->op_next->op_type], next));
                    code = push_gotorel(code, next);
                    /*dbg_lines1("logop_%d:", global_label);*/
                }
	    } else { /* special branches */
		int next;
                T_CHARARR push_arg1[] = { push_arg1_mem };
#  ifdef USE_ITHREADS
                T_CHARARR push_arg2[] = { push_arg2_mem };
#  endif
		switch (op->op_type) { 	/* sync this list with B::CC */
		case OP_FLIP:
                    DEBUG_v( printf("# flip_%d\n", global_label));
		    if ((op->op_flags & OPf_WANT) == OPf_WANT_LIST) {
                        /* need to check the returned op at runtime */
                        LOGOP* logop;
                        logop = cLOGOPx(cUNOPx(op)->op_first);
                        if (dryrun) {
                            int i = JIT_CHAIN_DRYRUN(logop->op_other);
			    size += i + sizeof_maybranch_check(i);
                            size += sizeof(GOTOREL);
                        } else {
                            int other;
                            other = JIT_CHAIN_DRYRUN(logop->op_other); /* sizeof other */
                            other += sizeof(GOTOREL);
                            code = push_maybranch_check(code, other); /* if cmp: je => next */
                            DEBUG_v( printf("# other_%d: %s, size=%x\n", global_label,
                                            PL_op_name[logop->op_other->op_type], PTR2X(other)));
                            code = JIT_CHAIN(logop->op_other);
                        }
		    }
		    break;
		/* store and jump to labels. */
		case OP_ENTERLOOP:
		case OP_ENTERITER:
                    if (!dryrun) {
                        int nextop, lastop, redoop;
                        LOOPTGT cx;
                        LOOP* loop;

                        loop = cLOOPx(op);
                        /* XXX Need to store away the branch targets in jmptargets, otherwise 
                           unjitted code is executed. 
                           We can also try to patchup the jmps afterwards.
                         */
                        DEBUG_v( printf("# %s_%d:\n", PL_op_name[loop->op_type], global_label));
                        /* After each chain jump to the end, so we need all sizes. */
                        nextop = JIT_CHAIN_DRYRUN(loop->op_nextop); /* sizeof other */
                        lastop = JIT_CHAIN_DRYRUN(loop->op_lastop);
                        redoop = JIT_CHAIN_DRYRUN(loop->op_redoop);
                        lsize = nextop + lastop + redoop + 3*(sizeof(CALL)+CALL_SIZE);
                        dbg_lines1("goto branch_%d;", global_label);
                        code = push_gotorel(code, lsize); /* jump to end: nextop+lastop+redoop+3*goto */

                        DEBUG_v( printf("# nextop_%d: %s, size=%x\n", global_label, 
                                        PL_op_name[loop->op_nextop->op_type], PTR2X(lsize)));
                        dbg_lines1("nextop_%d:", global_label);
                        cx.nextop = code;
                        code = JIT_CHAIN(loop->op_nextop);

                        lsize -= nextop + sizeof(CALL)+CALL_SIZE;
                        dbg_lines1("goto branch_%d;", global_label);
                        code = push_gotorel(code, lsize); /* jump to end */
                        DEBUG_v( printf("# lastop_%d: %s\tsize=%x\n", global_label, 
                                        PL_op_name[loop->op_lastop->op_type], PTR2X(lsize)));
                        cx.lastop = code;
                        dbg_lines1("lastop_%d:", global_label);
                        code = JIT_CHAIN(loop->op_lastop);

                        lsize -= lastop + sizeof(CALL)+CALL_SIZE;
                        dbg_lines1("goto branch_%d;", global_label);
                        code = push_gotorel(code, lsize); /* jump to end */
                        DEBUG_v( printf("# redoop_%d: %s, size=%x\n", global_label, 
                                        PL_op_name[loop->op_redoop->op_type], PTR2X(lsize)));
                        cx.redoop = code;
                        dbg_lines1("redoop_%d:", global_label);
                        code = JIT_CHAIN(loop->op_redoop);
                        PUSH_LOOP(cx);
                        dbg_lines1("branch_%d:", global_label);
                    }
		    break;
		case OP_SUBSTCONT: /* need to jit other and the PMREPLSTART. What logic? */ 
                    if (dryrun) {
                        size += JIT_CHAIN_DRYRUN(cLOGOPx(op)->op_other);
                    } else {
                        DEBUG_v( printf("# substcont other\n"));
                        code = JIT_CHAIN(cLOGOPx(op)->op_other);
                        /*size += next-(int)code;*/
                    }
#if PERL_VERSION > 8
# define PMREPLSTART(op) (op)->op_pmstashstartu.op_pmreplstart
#else
# define PMREPLSTART(op) (op)->op_pmreplstart
#endif
                    if (dryrun) {
                        size += JIT_CHAIN_DRYRUN(PMREPLSTART(cPMOPx(op)));
                    } else {
                        DEBUG_v( printf("# pmreplstart\n"));
                        code = JIT_CHAIN(PMREPLSTART(cPMOPx(op)));
                        /*size += lsize-(int)code;*/
                    }
                    break;

		case OP_NEXT:
		case OP_REDO:
		case OP_LAST:
                    /* XXX if not OPf_SPECIAL pop label op->pv from jmptargets (prev. called cxstack), 
                       else just next jmp */
                    if (dryrun) {
                        size += sizeof(GOTOREL);
                    } else {
                        LOOPTGT *cx;
                        CODE* tgtop;
                        cx = POP_LOOP;
                        if (op->op_type == OP_NEXT) tgtop = cx->nextop;
                        else if (op->op_type == OP_REDO) tgtop = cx->redoop;
                        else if (op->op_type == OP_LAST) tgtop = cx->lastop;
                        DEBUG_v( printf("# %s %x\n", PL_op_name[op->op_type], PTR2X(tgtop)));
                        code = push_gotorel(code, (int)tgtop); /* jmp or rel? */
                    }
                    break;
		case OP_ENTERSUB:
                    if (dryrun) {
                        size += sizeof(ifop0return);
                        size += sizeof(EPILOG);
                        size += sizeof(maybranch_check);
                        size += sizeof(add_eax_ppaddr);
                        size += sizeof(call_eax);
                        size += sizeof(SAVE_PLOP);
#if defined(JIT_CPU_AMD64) && !defined(USE_ITHREADS)
			size += MOV_SIZE;
#endif
                    } else {
			size = 0;
                        DEBUG_v( printf("# entersub: call unjitted sub\n") );
                        /* retval maybe DIE, check PL_op==0 */
                        dbg_lines("if (!PL_op)");
                        code = PUSHc(ifop0return);
                        dbg_lines("  return;");
                        code = PUSHc(EPILOG);
                        /* else */
                        dbg_lines1("if (PL_op == op) goto next_%d;", global_label);
                        /* XXX TODO check if we have jitted the returned %eax CvSTART */
                        /* (search for existing CvSTART targets) */
                        /* else call unjitted retval */
			size = sizeof(add_eax_ppaddr) + sizeof(call_eax);
                        size += sizeof(SAVE_PLOP);
#if defined(JIT_CPU_AMD64) && !defined(USE_ITHREADS)
			size += MOV_SIZE;
#endif
                        code = push_maybranch_check(code, size); /* if cmp: je => next */

#if defined(DEBUG_t_TEST_)
                        if (DEBUG_t_TEST_ && op) {
                            T_CHARARR push_arg1[] = { push_arg1_eax };
# ifdef USE_ITHREADS
                            T_CHARARR push_arg2[] = { push_arg2_eax };
# endif
                            if (dryrun) {
				PUSH_1ARG_DRYRUN;
                                size += sizeof(CALL) + CALL_SIZE;
                            } else {
				PUSH_1ARG;
                                CALL_ABS(&Perl_debop);
                                DEBUG_v( printf("# debop(%x) %s\n", PTR2X(op), (char*)PL_op_name[op->op_type]));
                                dbg_lines("debop(PL_op);");
                            }
                        }
#endif
                        dbg_lines("else (PL_op->op_ppaddr)();"); /* not found, continue unjitted */
                        PUSHc(add_eax_ppaddr); /* ppaddr offset from %eax */
                        PUSHc(call_eax);
                        PUSHc(SAVE_PLOP);
#if defined(JIT_CPU_AMD64) && !defined(USE_ITHREADS)
			PUSHrel(&PL_op);
#endif
                        dbg_lines1("next_%d:", global_label); 
                    }
                    break;

#if 0
                    /* XXX If we know the CvSTART, then we could jit the sub, then loop through it.
                       loop CvROOT until !PL_op or op->next */
                    {
                        OP* next = Perl_pp_entersub(aTHX); /* find CvSTART */
                        if (next) {
                            next = next->op_next;
                            if (dryrun) {
                                size += JIT_CHAIN_FULL_DRYRUN(next, opnext);
                            } else {
                                dbg_lines1("sub_%d: {", global_label);
                                lsize = JIT_CHAIN_FULL_DRYRUN(next, opnext);
                                code  = JIT_CHAIN_FULL(next, lsize, opnext);
                                dbg_lines("}");
                                dbg_lines1("next_%d:", global_label);
                            }
                        }
                    }
#endif
                    break;

                /* goto and other search at run-time 
                   for possible jump targets in jmptargets info.
                   If no cx record is found, continue with the unjitted OP.
                 */
		case OP_GOTO:
		    /* XXX We can only jump to jitted and recorded labels, else jump to unjitted code.
                       if (PL_op != ($sym)->op_next && PL_op != (OP*)0){return PL_op;} */
                    if (dryrun) {
                        int i = 0;
                        size += sizeof(ifop0return);
                        size += sizeof(EPILOG);
			PUSH_1ARG_DRYRUN;
                        i += PUSH_SIZE + sizeof(CALL) + CALL_SIZE;
                        i += sizeof(maybranch_check);
                        i += sizeof(GOTOREL);
                        size += i;

                    } else { /* get back a OP* address. but we can only jump to PUSH_CX ops */
                        CODE* jumptgt;
                        char *label;
                        OP *retop = NULL;
                        size = 0;

                        dbg_lines1("if (PL_op == op) goto next_%d;", global_label);
			PUSH_1ARG_DRYRUN;
                        size += PUSH_SIZE + sizeof(CALL) + CALL_SIZE;
                        size += sizeof(maybranch_check);
                        size += sizeof(GOTOREL);

                        code = PUSHc(ifop0return);
                        code = PUSHc(EPILOG);
                        code = push_maybranch_check(code, size); /* if cmp: je => next */

                        /* The retop with the found label is only retrieved dynamic, within jit.
                           so we need to call jmp_search_label to get the target */
                        if ((op->op_type == OP_GOTO) && !(op->op_flags & (OPf_STACKED|OPf_SPECIAL))) {
#ifdef DEBUGGING
                            label = ((PVOP*)op)->op_pv;
                            DEBUG_v( printf("# pp_goto %s via jmp_search_label(op)\n", label));
#endif
                        }
			PUSH_1ARG;
                        dbg_lines("unsigned char *jumptgt = jmp_search_label(op);");
                        PUSHabs(op);
                        CALL_ABS(&jmp_search_label);

                        dbg_lines("if (jumptgt) goto jumptgt");
                        dbg_lines("else (PL_op->op_ppaddr)();"); /* not found, continue unjitted */
                        code = push_gotorel(code, (int)jumptgt);

                        dbg_lines1("next_%d", global_label);
                    }
                    break;

                /* cx->blk_sub|eval|format.retop */
                case OP_RETURN:

                /* cx->blk_eval.retop */
                case OP_ENTEREVAL:
                case OP_ENTERTRY:

                /* cx->blk_givwhen.leaveop */
                case OP_LEAVEEVAL:

		default:
                    if (!dryrun) {
                        DEBUG_v( printf("NYI unsupported maybranch op %s\n", PL_op_name[op->op_type]) );
                    }
                    break;

	    }
#ifdef DEBUGGING
            global_label++;
#endif
            }
        NEXT:
            if (stopop) { /* entersub  loop until some op_next? */
                if (dryrun) {
                size += sizeof(maybranch_check);
                size += sizeof(GOTOREL);
                } else {
                    DEBUG_v( printf("#  check !PL_op or PL_op 0x%x != op->next 0x%x (entersub)\n",
                                    PTR2X(opnext), PTR2X(stopop)));
                    int i = sizeof(maybranch_check);
                    i += sizeof(GOTOREL);
                    code = push_maybranch_check(code, i);
                    code = push_gotorel(code, jumpsize);
                    dbg_lines1("if (PL_op == op) goto next_%d;", global_label);
                }
                if (stopop == opnext) goto OUT;
            } /* stopop */
        } /* maybranch */
	op = opnext;
    } while (op);
 OUT:
    if (dryrun) { 
        op = startop;
        return size;
    } else {
        return (long)code;
    }
}

/*
Faster jitted execution path without loop,
selected with -MJit or (later) with perl -j.

All ops are unrolled in execution order for the CPU cache,
prefetching is the main advantage of this function.
The ASYNC check is only done when necessary.

For now only implemented for x86/amd64 with certain hardcoded
my_perl offsets for threaded perls.
XXX Need to check offsets for older threaded perls.
*/
int
Perl_runops_jit(pTHX)
{
#ifdef dVAR
    dVAR;
#endif
#ifdef DEBUGGING
    static int line = 0;
    register int i;
    FILE *fh;
    char *opname;
#if defined(DEBUGGING) && defined(__GNUC__)
    FILE *stabs;
#endif
#endif
    U32 rel; /* 4 byte int */
    CODE *code, *code_start;
    OP *root;
    int pagesize = 4096, size = 0;
#ifdef PROFILING
    SV *sv_prof;
    NV bench;
    int profiling = 1; /* default on, but can be turned off via $Jit::_profiling=0; */
    sv_prof = get_sv("Jit::_profiling", 0);
    if (sv_prof) {
        profiling = SvIV_nomg(sv_prof);
    }
#endif

    if (!(PL_hints & HINT_JIT_FLAGS)) {
        register OP* op;
        while ((PL_op = op = op->op_ppaddr(aTHX))) {
        }
        TAINT_NOT;
        return 0;
    }

#ifdef DEBUGGING
# if PERL_VERSION > 11
    if (!PL_op) {
	Perl_ck_warner_d(aTHX_ packWARN(WARN_DEBUGGING), "NULL OP IN JIT RUN");
	return 0;
    }
# endif
    DEBUG_l(Perl_deb(aTHX_ "Entering new RUNOPS JIT level\n"));
#endif

    /* quirky pass 1: need size to allocate code.
       PL_slab_count should be near the optree size, but our method is safe.
       Need to time that against an realloc checker in pass 2.
     */
    code = 0;
#ifdef DEBUGGING
    fh = fopen("run-jit.c", "a");
    fprintf(fh,
            "struct op { OP* op_next; OP* op_other } OP;"
# ifdef USE_ITHREADS
	    "struct PerlInterpreter { OP* IOp; int Isig_pending; };"
# endif
# if (PERL_VERSION > 6) && (PERL_VERSION < 13)
	    "void *PL_sig_pending;"
# endif
            "OP *PL_op; void runops_jit_%d (void);\n"
	    "void runops_jit_%d (void){ OP* op;\n"
            , global_loops, global_loops);
    line += 2;
#endif
    root = PL_op;
#ifdef PROFILING
    if (profiling) {
        bench = mytime();
    }
#endif
    size = 0;
    size += sizeof(PROLOG);
    size += JIT_CHAIN_DRYRUN(PL_op);
    size += sizeof(EPILOG);
    while ((size | 0xfffffff0) % PTRSIZE) { 
        size++;
    }
#ifdef _WIN32
    code = VirtualAlloc(NULL, size,
			MEM_COMMIT | MEM_RESERVE,
			PAGE_EXECUTE_READWRITE);
#else
  /* amd64/linux+bsd disallow mprotect'ing an unaligned heap. Windows/cygwin even on i386.
     We NEED to start it in a fresh new page. */
# ifdef HAS_GETPAGESIZE
    pagesize = getpagesize();
# endif
# ifdef HAVE_MEMALIGN
    code = (char*)memalign(pagesize, size*sizeof(char));
# else
#  ifdef HAVE_POSIX_MEMALIGN
    if (posix_memalign((void**)&code, pagesize, size*sizeof(char))) {
        croak("posix_memalign(code,%d,%d) failed", pagesize, size);
    }
#  else
    /* e.g. openbsd has no memalign, but aligns automatically to page boundary 
       if the size is "big enough", around the pagesize. */
    if (size < pagesize) size = pagesize;
    code = (char*)malloc(size);
    if ((int)code & (pagesize-1)) { /* need to align it manually to 0x1000 */
        int newsize = pagesize - ((int)code & (pagesize-1));
        free(code);
        code = (char*)malloc(size + newsize);
        DEBUG_v( printf("# manually align code=0x%x newsize=%x\n",PTR2X(code), PTR2X(size + newsize)) );
        if ((int)code & (pagesize-1)) {
            /* hardcode pagesize = 4096 */
#   if PTRSIZE == 4
            code = (char*)(((int)code & 0xfffff000) + 0x1000);
#   else
            code = (char*)(((int)code & 0xfffffffffffff000) + 0x1000);
#   endif
            DEBUG_v( printf("# re-aligned stripped code=0x%x size=%u\n",PTR2X(code), size) );
        }
    }
#  endif
# endif
#endif
    code_start = code;

#if defined(DEBUGGING) && defined(__GNUC__)
    stabs = fopen("run-jit.s", "a");
    /* filename info */
    fprintf(stabs, ".data\n.text\n");       			/* darwin needs that */
    fprintf(stabs, ".file  \"run-jit.c\"\n");
    fprintf(stabs, ".stabs \"%s\",100,0,0,0\n", "run-jit.c");   /* filename */
    /* jit_func start addr */
    fprintf(stabs, ".stabs \"runops_jit_%d:F(0,1)\",36,0,2,%p\n",
	    global_loops, code);
    fprintf(stabs, ".stabs \"Void:t(0,0)=(0,1)\",128,0,0,0\n"); /* stack variable types */
    fprintf(stabs, ".stabs \"struct op:t(0,5)=*(0,6)\",128,0,0,0\n");
# ifdef USE_ITHREADS
    fprintf(stabs, ".stabs \"PerlInterpreter:S(0,12)\",38,0,0,%p\n", /* variable in data section */
#  ifdef MOV_REL
            0 /*(CODE*)&my_perl - code*/
#  else
            (char*)&my_perl
#  endif
	    );
# endif
    fprintf(stabs, ".stabn 68,0,%d,0\n", line);
#endif
#ifdef PROFILING
    if (profiling) {
        printf("jit pass 1:\t%0.12f\n", mytime() - bench);
        bench = mytime();
    }
#endif

    /* pass 2: jit */
    code = push_prolog(code);
    PL_op = root;
    code = JIT_CHAIN(PL_op);
    PUSHc(EPILOG);
    while (((unsigned int)code | 0xfffffff0) % PTRSIZE) { *(code++) = NOP[0]; }
    /* XXX TODO patchup missed jmp or sub or loop targets */

#ifdef PROFILING
    if (profiling) {
        printf("jit pass 2:\t%0.12f\n", mytime() - bench);
        bench = mytime();
    }
#endif

#ifdef DEBUGGING
    fprintf(fh, "}\n");
    line++;
    fclose(fh);
# if defined(DEBUGGING) && defined(__GNUC__)
    fprintf(stabs, ".stabs \"\",36,0,1,%p\n", (char *)size); /* eof */
    /* for stabs: as run-jit.s; gdb add-symbol-file run-jit.o 0 */
    fclose(stabs);
    system("as run-jit.s -o run-jit.o");
# endif
# ifdef HAVE_DISPATCH
    DEBUG_v( printf("# Perl_despatch_signals \t= 0x%x\n",
                    PTR2X(Perl_despatch_signals)) );
#  if !defined(USE_ITHREADS)
    DEBUG_v( printf("# &PL_sig_pending \t= 0x%x\n", PTR2X(&PL_sig_pending)) );
#  endif
# endif
    global_loops++;    
#endif
    if (jmptargets) free(jmptargets);
    if (looptargets) free(looptargets);
    /*I_ASSERT(size == (code - code_start));*/
    /*size = code - code_start;*/

    PL_op = root;
    code = code_start;
#ifdef HAS_MPROTECT
    if (mprotect(code,size*sizeof(char),PROT_EXEC|PROT_READ|PROT_WRITE) < 0)
	croak ("mprotect code=0x%x for size=%u failed", PTR2X(code), size);
#endif
    /* XXX Missing. Prepare for execution: flush CPU cache. Needed only on ppc32 and ppc64 */

    /* gdb: disassemble code code+200 */
#if defined(DEBUGGING) && defined(DEBUG_v_TEST)
    if (DEBUG_v_TEST) {
        DEBUG_v( printf("# &PL_op   \t= 0x%x / *0x%x\n", PTR2X(&PL_op), PTR2X(PL_op)) );
        DEBUG_t( printf("# debop   \t= 0x%x\n", PTR2X(&Perl_debop)) );
# ifdef USE_ITHREADS
        DEBUG_v( printf("# &my_perl \t= 0x%x / *0x%x\n", PTR2X(&my_perl), PTR2X(my_perl)) );
# endif
        DEBUG_v( printf("# code() 0x%x size %d (0x%x)",PTR2X(code),PTR2X(size),PTR2X(size)) );
# ifndef HAVE_LIBDISASM
        for (i=0; i < size; i++) {
            if (!(i % 8)) DEBUG_v( printf("\n#(code+%3x): ", i) );
            DEBUG_v( printf("%02x ",PTR2X(code[i])) );
        }
# endif
        DEBUG_v( printf("\n# runops_jit_%d\n",global_loops-1) );
    }

    /* How to disassemble per command line:
       echo "55 89 e5 53 51 83 ec 08" |xxd -r -p - > xx
       objdump -D --target=binary --architecture i386:intel xx

   0:   55                      push   ebp
   1:   89 e5                   mov    ebp,esp
   3:   53                      push   ebx
   4:   51                      push   ecx
   5:   83 ec 08                sub    esp,0x8

     */
    if (DEBUG_v_TEST) {
# ifdef HAVE_LIBDISASM
#  define LINE_SIZE 255
	char line[LINE_SIZE];
	int pos = 0;
	int insnsize;            /* size of instruction */
	x86_insn_t insn;         /* one instruction */

	x86_init(opt_none, NULL, NULL);
	while ( pos < size ) {
	    insnsize = x86_disasm(code, size, 0, pos, &insn);
	    if ( insnsize ) {
		x86_format_insn(&insn, line, LINE_SIZE, att_syntax);
		printf("#(code+%3x): ", pos);
		for ( i = 0; i < 10; i++ ) {
		    if ( i < insn.size ) printf(" %02x", insn.bytes[i]);
		    else printf("   ");
		}
		printf("%s\n", line);
		pos += insnsize;
	    } else {
		printf("# Invalid instruction at 0x%x. size=0x%x\n", pos, size);
		pos++;
	    }
	}
	x86_cleanup();
# else
	fh = fopen("run-jit.bin", "w");
        fwrite(code,size,1,fh);
        fclose(fh);
        system("objdump -D --target=binary --architecture i386"
#  ifdef JIT_CPU_AMD64
               ":x86-64"
#  endif
               " run-jit.bin");
# endif
    }
#endif

/*================= Jit.xs:1486 runops_jit_0 == disassemble code code+40 =====*/
    (*((void (*)(pTHX))code))(aTHX);
/*================= runops_jit ==============================================*/
    DEBUG_l(Perl_deb(aTHX_ "leaving RUNOPS JIT level\n"));
#ifdef PROFILING
    if (profiling) {
        printf("jit runloop:\t%0.12f\n", mytime() - bench);
        bench = mytime();
    }
#endif

    TAINT_NOT;
#ifdef _WIN32
    VirtualFree(code, 0, MEM_RELEASE);
#else
    free(code);
#endif
    if (otherops)
        sv_free((SV*)otherops);
    if (otherops1)
        sv_free((SV*)otherops1);

#ifdef PROFILING
    if (profiling) {
        PL_op = root;
        register OP *op = PL_op;
        while ((PL_op = op = op->op_ppaddr(aTHX))) {
        }
        printf("unjit runloop:\t%0.12f\n", mytime() - bench);
    }
#endif

    return 0;
}

MODULE=Jit 	PACKAGE=Jit

PROTOTYPES: DISABLE

BOOT:
    unsigned long hints;
#ifdef DEBUGGING
# ifdef __GNUC__
    struct stat statbuf;
# endif
    unlink("run-jit.c");
# ifdef __GNUC__
    if (!stat("run-jit.s", &statbuf))
        unlink("run-jit.s");
# endif
#endif
#ifdef JIT_CPU
    sv_setsv(get_sv("Jit::HINT_JIT_FLAGS", GV_ADD), newSViv(HINT_JIT_FLAGS));
    sv_setsv(get_sv("Jit::CPU", GV_ADD), newSVpv(JIT_CPU, 0));
    /* jit main::* ? */
    if (PL_hints & HINT_JIT_FLAGS) {
      PL_runops = Perl_runops_jit;
    }
#endif
