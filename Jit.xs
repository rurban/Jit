/*    Jit.xs -*- mode:C c-basic-offset:4 -*-
 *
 *    JIT (Just-in-time compile) the Perl5 runloop.
 *    Currently for x86 32bit, amd64 64bit. More CPU's later.
 *    Status:
 *      Works only for simple i386 and amd64 (amd64 threaded fails), 
 *      without PERL_ASYNC_CHECK,
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

#define T_CHARARR static unsigned char
#define T_UC 	  unsigned char
#undef JIT_CPU
/* if dealing with doubles on sse we want this */
#define ALIGN_16(c) (c%16?(c+(16-c%16)):c) 
#define ALIGN_64(c) (c%64?(c+(64-c%64)):c) 
#define ALIGN_N(n,c) (c%n?(c+(n-c%n)):c) 

int dispatch_needed(OP* op);
int maybranch(OP* op);
unsigned char *push_prolog(unsigned char *code);
long jit_chain(pTHX_ OP* op, unsigned char *code, unsigned char *code_start
#ifdef DEBUGGING
              ,FILE *fh, FILE *stabs
#endif
              );

/* When do we need PERL_ASYNC_CHECK?
 * if (dispatch_needed(op)) if (PL_sig_pending) Perl_despatch_signals();
 *
 * Until 5.13.2 we had it after each and every op,
 * since 5.13.2 only inside certain ops,
 *   which need to handle pending signals.
 * In 5.6 it was a NOOP.
 */
/*#define BYPASS_DISPATCH */ /* test ok on i386, not yet tested on amd64 */
#if (PERL_VERSION > 6) && (PERL_VERSION < 13)
#define HAVE_DISPATCH
#define DISPATCH_NEEDED(op) dispatch_needed(op)
#else
#undef HAVE_DISPATCH
#define DISPATCH_NEEDED(op) 0
#endif

#ifdef DEBUGGING
# define JIT_CHAIN(op, code, code_start) jit_chain(aTHX_ op, code, code_start, fh, stabs)
# define DEB_PRINT_LOC(loc) printf(loc" \t= 0x%x\n", loc)
# if PERL_VERSION < 8
#   define DEBUG_v(x) x
# endif
#else
# define JIT_CHAIN(op, code, code_start) jit_chain(aTHX_ op, code, code_start) 
# define DEB_PRINT_LOC(loc)
#endif

/*
C pseudocode of the Perl runloop:

not-threaded:

  OP *op;
  int *p = &Perl_Isig_pending_ptr;
if maybranch:
  op = PL_op;
  PL_op = Perl_pp_opname();  #returns op_next, op_other, op_first, op_last or a new optree start
  if dispatch_needed: if (*p) Perl_despatch_signals();
    if (PL_op == op) 	#if maybranch label other targets
        goto next_1;
    #assemble op_other chain until 0
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
#endif

#define CALL_ABS(abs) 	code = call_abs(code,abs)
/*(U32)((unsigned char*)abs-code-3)*/
#define PUSHc(what) memcpy(code,what,sizeof(what)); code += sizeof(what)
/* force 4 byte for U32, 64bit uses 8 byte for U32, but 4 byte for call near */
#define PUSHcall(what) memcpy(code,&what,CALL_SIZE); code += CALL_SIZE

/* __amd64 defines __x86_64 */
#if defined(__x86_64__) || defined(__amd64) || defined(__amd64__) || defined(_M_X64)
#define JIT_CPU "amd64"
#define JIT_CPU_AMD64
#define CALL_ALIGN 0
#define MOV_REL
#define PUSH_SIZE  4				/* size for the push instruction arg 4/8 */

/* yet untested! */
#define BYPASS_DISPATCH

#define PUSHabs(what) memcpy(code,what,PUSH_SIZE); code += PUSH_SIZE
#define PUSHrel(where) { \
    U32 r = (unsigned char*)where - (code+MOV_SIZE);	\
    memcpy(code,&r,MOV_SIZE); code += MOV_SIZE; \
}
/*void f_PUSHrel(unsigned char* code, void *where);*/
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
#define push_rbp    	0x55
#define mov_rsp_rbp 	0x48,0x89,0xe5
#define push_r12 	0x41,0x54
#define push_rbx 	0x53
#define push_rcx	0x51
#define sub_x_rsp(byte) 0x48,0x83,0xec,byte
#define add_x_esp(byte) 0x48,0x83,0xc4,byte
#define fourbyte        0x00,0x00,0x00,0x00
#define mov_mem_eax(m)	0xa1,revword(m)
/* mov    $memabs,(%ebx) &PL_op in ebx */
#define mov_mem_rbx     0x48,0x8b,0x1d /* mov &PL_op,%rbx */
#define mov_rebp_ebx(byte) 0x8b,0x5d,byte  /* mov 0x8(%ebp),%ebx*/
#define mov_rrsp_rbx    0x48,0x8b,0x1c,0x24    /* mov    (%rsp),%rbx ; my_perl from stack to rbx */

#define push_imm_0	0x68
#define push_imm(m)	0x68,revword(m)
/* gcc __fastcall amd64 convention for param 1-2 passing */
#define mov_mem_esi     0xbe		/* arg2 */
#define mov_mem_edi     0xbf		/* arg1 */
#define mov_mem_ecx	0xb9      	/* arg1 */
#ifndef _WIN64
#define push_arg1_mem   mov_mem_edi	/* if call via register */
#define push_arg2_mem   mov_mem_esi
#else
/* Win64 Visual C __fastcall uses rcx,rdx for the first int args, not rdi,rsi
   We use less than 2GB for our vars and subs.
 */
#define mov_mem_edx     0xba		/* arg2 */
#define push_arg1_mem   mov_mem_ecx	/* if call via register */
#define push_arg2_mem   mov_mem_edx
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
#define mov_eax_4ebp 	0x89,0x45,0xfc

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
#define jmp(byte)       0x3b,(byte) /* maybranch, untested */
/* mov    %rax,(%rbx) &PL_op in ebx */
#define mov_rax_memr    0x48,0x89,0x05 /* + 4 rel */
#define mov_eax_rebx    0x89,0x03

#define mov_4ebp_edx    0x8b,0x55,0xfc
#define mov_reax_ebx    0x48,0x8b,0x18
#define mov_redx_eax    0x82,0x02
#define test_eax_eax    0x85,0xc0
#define je(byte)        0x74,(byte)
/* skip call	_Perl_despatch_signals */

#ifdef USE_ITHREADS
# include "amd64thr.c"
#else
# include "amd64.c"
#endif

#endif

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

/* PROLOG */
#define push_ebp    	0x55
#define mov_esp_ebp 	0x89,0xe5
#define push_edi 	0x57
#define push_esi	0x56
#define push_ebx 	0x53
#define push_ecx	0x51
#define sub_x_esp(byte) 0x83,0xec,byte
#define mov_eax_rebx	0x89,0x03	/* mov    %rax,(%rbx) &PL_op in ebx */

#define push_imm_0	0x68
#define push_imm(m)	0x68,revword(m)
#define push_arg1_mem   push_imm_0
#define push_arg2_mem   push_imm_0

/* mov    $memabs,%eax PL_op in eax */
#define mov_mem_eax(m)	0xa1,revword(m)
/* mov    $memabs,%ebx &PL_op in ebx */
#define mov_mem_ebx(m)	0xbb,revword(m)
#define mov_mem_ecx(m)	0xb9,revword(m)
/* &PL_sig_pending in -4(%ebp) */
#define mov_mem_4ebp(m)	0xc7,0x45,0xfc,revword(m)
/*#define mov_mem_ecx 	0x8b,0x0d*/
#define mov_4ebp_edx	0x8b,0x55,0xfc
#define mov_redx_eax	0x8b,0x02
#define test_eax_eax    0x85,0xc0
#define je(byte) 	0x74,(byte)
#define mov_rebp_ebx(byte) 0x8b,0x5d,byte  /* mov 0x8(%ebp),%ebx*/

/* EPILOG */
#define add_x_esp(byte) 0x83,0xc4,byte	/* add    $0x4,%esp */
#define pop_ecx    	0x59
#define pop_ebx 	0x5b
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
#define mov_eax_mem 	0xa3	    /* + 4 memabs */
#define jmp(byte)       0x3b,(byte) /* maybranch */

#ifdef USE_ITHREADS
# include "i386thr.c"
#else
# include "i386.c"
#endif
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
    U32 r = (unsigned char*)where - (code+4); \
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
    switch (op->op_type) { 	/* sync this list with Opcodes-0.04 */
    case OP_SUBST:
    case OP_SUBSTCONT:
    case OP_DEFINED:
    case OP_FORMLINE:
    case OP_GREPSTART:
    case OP_GREPWHILE:
    case OP_MAPWHILE:
    case OP_AND:
    case OP_OR:
    case OP_COND_EXPR:
    case OP_ANDASSIGN:
    case OP_ORASSIGN:
#if PERL_VERSION > 8
    case OP_DOR:
    case OP_DORASSIGN:
#endif
    case OP_DBSTATE:
    case OP_RETURN:
    case OP_LAST:
    case OP_NEXT:
    case OP_REDO:
    case OP_DUMP:
    case OP_GOTO:
    case OP_REQUIRE: /* ? */
    case OP_ENTEREVAL:
    case OP_ENTERTRY:
#if PERL_VERSION > 8
    case OP_ENTERWHEN:
    case OP_ONCE:
#endif
        return 1;
    default:
        return 0;
    }
}

int
returnother(OP* op) {
    switch (op->op_type) { 	/* sync this list with B::CC */
    case OP_AND:
    case OP_OR:
#if PERL_VERSION > 8
    case OP_DOR:
    case OP_DORASSIGN:
#endif
    case OP_COND_EXPR:
    case OP_ANDASSIGN:
    case OP_ORASSIGN:
	return 1;
    default:
	return 0;
    }
}

unsigned char *
call_abs (unsigned char *code, void *addr) {
    /* intel specific: */
    register signed long rel = (unsigned char*)addr - code - sizeof(CALL) - CALL_SIZE;
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

long
jit_chain(pTHX_
	  OP *op,
	  unsigned char *code, 
	  unsigned char *code_start
#ifdef DEBUGGING
	  ,FILE *fh, FILE *stabs
#endif
	  )
{
    int dryrun = !code;
    int size = 0;
#ifdef DEBUGGING
    static int line = 3;
    char *opname;

    if (!dryrun) {
	opname = (char*)PL_op_name[op->op_type];
        fprintf(fh, "/* block jit_chain op 0x%x pp_%s; */\n", op, opname);
        line++;
    }
#endif

    do {
#ifdef DEBUGGING
	if (!dryrun) {
	    opname = (char*)PL_op_name[op->op_type];
	    DEBUG_v( printf("# pp_%s \t= 0x%x / 0x%x\n", opname, op->op_ppaddr, op));
	}
# if defined(DEBUG_s_TEST_)
        if (DEBUG_s_TEST_) {
#  ifdef USE_ITHREADS
            T_CHARARR push_arg1[] = { push_arg1_mem };
#  endif
            if (dryrun) {
#  ifdef USE_ITHREADS
                size += sizeof(push_arg1); size += CALL_SIZE;
#  endif
                size += sizeof(CALL); size += CALL_SIZE;
            } else {
#  ifdef USE_ITHREADS
                PUSHc(push_arg1);
                PUSHabs(&my_perl);
#  endif
                CALL_ABS(&Perl_debstack);
#  if defined(__GNUC__)
                fprintf(fh, "debstack();\n");
                fprintf(stabs, ".stabn 68,0,%d,%d /* Perl_debstack(aTHX) */\n",
                        ++line, code-code_start);
#  endif
            }
        }
        if (DEBUG_t_TEST_) {
            T_CHARARR push_arg1[] = { push_arg1_mem };
#  ifdef USE_ITHREADS
            T_CHARARR push_arg2[] = { push_arg2_mem };
#  endif
            if (dryrun) {
                size += sizeof(push_arg1); size += CALL_SIZE;
#  ifdef USE_ITHREADS
                size += sizeof(push_arg2); size += CALL_SIZE;
#  endif
                size += sizeof(CALL); size += CALL_SIZE;
            } else {
                if (op) {
#  ifdef USE_ITHREADS
                    PUSHc(push_arg2);
                    PUSHabs(op);
                    PUSHc(push_arg1);
                    PUSHabs(&my_perl);
#  else
                    PUSHc(push_arg1);
                    PUSHabs(op);
#  endif
                    CALL_ABS(&Perl_debop);
                    DEBUG_v( printf("# debop(%x) %s\n", op, (char*)PL_op_name[op->op_type]));
                }
#  if defined(__GNUC__)
                fprintf(fh, "debop(PL_op);\n");
                fprintf(stabs, ".stabn 68,0,%d,%d /* Perl_debop(aTHX_ PL_op) */\n",
                        ++line, code-code_start);
#  endif
            }
        }
# endif
#endif

	if (op->op_type == OP_NULL) continue;
#if defined(DEBUGGING) && defined(__GNUC__)
	if (!dryrun) {
	    fprintf(stabs, ".stabn 68,0,%d,%d /* call pp_%s */\n",
		    ++line, code-code_start, opname);
	}
#endif
	
	if (!dryrun) {
#ifdef DEBUGGING
# ifdef USE_ITHREADS
	    fprintf(fh, "my_perl->Iop = Perl_pp_%s(my_perl);\n", opname);
# else
	    fprintf(fh, "PL_op = Perl_pp_%s();\n", opname);
# endif
#endif
	}
	if (dryrun) {
	    size += sizeof(CALL); size += CALL_SIZE;
	} else {
	    CALL_ABS(op->op_ppaddr);
#if defined(DEBUGGING) && defined(__GNUC__)
	    fprintf(stabs, ".stabn 68,0,%d,%d /* PL_op = eax */\n",
		    ++line, code-code_start);
#endif
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
#ifdef DEBUGGING
	    if (!dryrun) {
# ifdef USE_ITHREADS
		fprintf(fh, "if (my_perl->Isig_pending)\n  Perl_despatch_signals(my_perl);\n");
# else
		fprintf(fh, "if (PL_sig_pending)\n  Perl_despatch_signals();\n");
# endif
# ifdef __GNUC__
		fprintf(stabs, ".stabn 68,0,%d,%d /* if (PL_sig_pending) */\n",
			++line, code-code_start);
# endif
	    }
#endif
# ifndef USE_ITHREADS
#  ifdef DISPATCH_GETSIG
	    if (dryrun) {
		size += sizeof(DISPATCH_GETSIG);
		size += MOV_SIZE;
	    } else {
		PUSHc(DISPATCH_GETSIG);
		PUSHrel(&PL_sig_pending);
	    }
#  endif
# endif
	    if (dryrun) {
		size += sizeof(DISPATCH) + sizeof(CALL) + CALL_SIZE;
	    } else {
		PUSHc(DISPATCH);
		CALL_ABS(&Perl_despatch_signals);
#   if defined(DEBUGGING) && defined(__GNUC__)
		fprintf(stabs, ".stabn 68,0,%d,%d /* Perl_despatch_signals() */\n",
			++line, code-code_start);
#   endif
	    }
# if defined(USE_ITHREADS) && defined(DISPATCH_POST)
	    if (dryrun) {
		size += sizeof(DISPATCH_POST);
	    } else {
		PUSHc(DISPATCH_POST);
	    }
# endif
        }
#endif

        /* other before next */
	if (maybranch(op)) {
            int label;
	    if (dryrun) {
		size += sizeof(maybranch_plop) + sizeof(CALL) + CALL_SIZE;
	    } else {
		code = push_maybranch_plop(code);
		CALL_ABS(op->op_ppaddr);
	    }
	    if ((PL_opargs[op->op_type] & OA_CLASS_MASK) == OA_LOGOP) {
		/* TODO store and jump to labels */
                if (dryrun) {
                    size += sizeof(GOTOREL);
                    size += JIT_CHAIN(cLOGOPx(op)->op_other, NULL, NULL);
                    size += sizeof(GOTOREL);
                } else {
                    /* XXX TODO cmp returned op => je */
                    int next = JIT_CHAIN(cLOGOPx(op)->op_other, NULL, NULL);
                    code = push_gotorel(code, next);
                    code = (unsigned char*)JIT_CHAIN(cLOGOPx(op)->op_other, code, code_start);
                    next = JIT_CHAIN(cLOGOPx(op)->op_next, code, code_start);
                    code = push_gotorel(code, (long)code+next);
                }
	    } else {
		int next, label;
		/* need to check the returned op at runtime? we'd need an indirect call then. */
		switch (op->op_type) { 	/* sync this list with B::CC */
		case OP_FLIP:
		    if ((op->op_flags & OPf_WANT) == OPf_WANT_LIST) {
                        if (!dryrun) {
                            label = JIT_CHAIN(cLOGOPx(cUNOPx(op)->op_first)->op_other, code, code_start);
                            size += label-(int)code;
                            code = (unsigned char *)label;
                        }
		    }
		    break;
		case OP_ENTERLOOP:
		case OP_ENTERITER:
                    if (!dryrun) {
                        label = JIT_CHAIN(cLOOPx(op)->op_nextop, code, code_start);
                        size += label-(int)code;
                        label = JIT_CHAIN(cLOOPx(op)->op_lastop, (char*)label, code_start);
                        size += label-(int)code;
                        label = JIT_CHAIN(cLOOPx(op)->op_redoop, (char*)label, code_start);
                        size += label-(int)code;
                    }
		    break;
		case OP_SUBSTCONT:
                    if (!dryrun) {
                        next = JIT_CHAIN(cLOGOPx(op)->op_other, code, code_start);
                        size += next-(int)code;
                    }
#if PERL_VERSION > 8
# define PMREPLSTART(op) (op)->op_pmstashstartu.op_pmreplstart
#else
# define PMREPLSTART(op) (op)->op_pmreplstart
#endif
                    if (!dryrun) {
                        label = JIT_CHAIN(PMREPLSTART(cPMOPx(op)), code, code_start);
                        size += label-(int)code;
                    }
		    /* TODO runtime check: goto label, else return next->next */
		case OP_GOTO:
		    /* TODO runtime check: goto label */
		default:
		    warn("unsupport branch for %s", PL_op_name[op->op_type]);
		}
	    }
	}
    } while (op = op->op_next);
    return dryrun ? size : (int)code;
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
    static int global_loops = 0;
    register int i;
    FILE *fh;
    char *opname;
#if defined(DEBUGGING) && defined(__GNUC__)
    FILE *stabs;
#endif
#endif
    U32 rel; /* 4 byte int */
    unsigned char *code, *code_start;
    OP *root;
    int pagesize = 4096, size = 0;
#ifdef PROFILING
    SV *sv_prof;
    int profiling = 1;
    NV bench;
    sv_prof = get_sv("Jit::_profiling", 0);
    if (sv_prof) {
        profiling = SvIV_nomg(sv_prof);
    }
#endif

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
    fprintf(fh, "void *PL_op%s; void runops_jit_%d (void);\n"
	    "void runops_jit_%d (void){\n",
#if (PERL_VERSION > 6) && (PERL_VERSION < 13)
	    ", *PL_sig_pending",
#else
	    "",
#endif
            global_loops, global_loops);
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
    size += JIT_CHAIN(PL_op, NULL, NULL);
    size += sizeof(EPILOG);
    while ((size | 0xfffffff0) % 4) { size++; }
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
    code = (char*)posix_memalign(pagesize, size*sizeof(char));
#  else
    code = (char*)malloc(size);
    if ((int)code & (pagesize-1)) { /* need to align it manually to 0x1000 */
        int newsize = pagesize - ((int)code & (pagesize-1));
        free(code);
        code = (char*)malloc(size + newsize);
        DEBUG_v( printf("# manually align code=0x%x newsize=%x\n",code, size + newsize) );
        if ((int)code & (pagesize-1)) {
            /* hardcode pagesize = 4096 */
#if PTRSIZE == 4
            code = (char*)(((int)code & 0xfffff000) + 0x1000);
#else
            code = (char*)(((int)code & 0xfffffffffffff000) + 0x1000);
#endif
            DEBUG_v( printf("# re-aligned stripped code=0x%x size=%u\n",code, size) );
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
            0 /*(unsigned char*)&my_perl - code*/
#  else
            (char*)&my_perl
#  endif
	    );
# endif
    fprintf(stabs, ".stabn 68,0,%d,0\n", line);
    global_loops++;
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
    code = (unsigned char*)JIT_CHAIN(PL_op, code, code_start);
    PUSHc(EPILOG);
    while (((unsigned int)&code | 0xfffffff0) % 4) { *(code++) = NOP[0]; }

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
                    Perl_despatch_signals) );
#  if !defined(USE_ITHREADS)
    DEBUG_v( printf("# &PL_sig_pending \t= 0x%x\n", &PL_sig_pending) );
#  endif
# endif
#endif
    /*I_ASSERT(size == (code - code_start));*/
    /*size = code - code_start;*/

    PL_op = root;
    code = code_start;
#ifdef HAS_MPROTECT
    if (mprotect(code,size*sizeof(char),PROT_EXEC|PROT_READ|PROT_WRITE) < 0)
	croak ("mprotect code=0x%x for size=%u failed", code, size);
#endif
    /* XXX Missing. Prepare for execution: flush CPU cache. Needed only on ppc32 and ppc64 */

    /* gdb: disassemble code code+200 */
#if defined(DEBUGGING) && defined(DEBUG_v_TEST)
    if (DEBUG_v_TEST) {
        DEBUG_v( printf("# &PL_op   \t= 0x%x / *0x%x\n",&PL_op, PL_op) );
#ifdef USE_ITHREADS
        DEBUG_v( printf("# &my_perl \t= 0x%x / *0x%x\n",&my_perl, my_perl) );
#endif
        DEBUG_v( printf("# code() 0x%x size %d",code,size) );
        for (i=0; i < size; i++) {
            if (!(i % 8)) DEBUG_v( printf("\n#(code+%3d): ", i) );
            DEBUG_v( printf("%02x ",code[i]) );
        }
        DEBUG_v( printf("\n# runops_jit_%d\n", global_loops-1) );
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
        fh = fopen("run-jit.bin", "w");
        fwrite(code,size,1,fh);
        fclose(fh);
        system("objdump -D --target=binary --architecture i386"
#ifdef JIT_CPU_AMD64
               ":x86-64"
#endif
               " run-jit.bin");
    }

#endif

/*================= Jit.xs:859 runops_jit_0 == disassemble code code+40 =====*/
    (*((void (*)(pTHX))code))(aTHX);
/*================= runops_jit =================================*/
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
    sv_setsv(get_sv("Jit::CPU", GV_ADD), newSVpv(JIT_CPU, 0));
    PL_runops = Perl_runops_jit;
#endif
