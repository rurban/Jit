/*    Jit.xs -*- C -*-
 *
 *    Copyright (C) 2010 by Reini Urban
 *    JIT the Perl5 runloop. 
 *    Currently for x86 32bit, amd64 64bit. More CPU's later.
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
#undef JIT_CPU
#define STACK_SPACE 0x08   /* private area, not yet used */

int dispatch_needed(OP* op);

/* When do we need PERL_ASYNC_CHECK?
 * Until 5.13.2  we had it after each and every op,
 * since 5.13.2 only inside certain ops,
 * which need to handle pending signals.
 * In 5.6 it was a NOOP
 */
#if (PERL_VERSION > 6) && (PERL_VERSION < 13)
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
  C pseudocode of the Perl runloop:

  threaded:
    my_perl->Iop = <PL_op->op_ppaddr>(my_perl);
    if (my_perl->Isig_pending) Perl_despatch_signals(my_perl);

  not-threaded:
    PL_op = <PL_op->op_ppaddr>();
    if (PL_sig_pending) Perl_despatch_signals();
*/

#if (defined(__i386__) || defined(_M_IX86))
#define JIT_CPU "i386"
#define CALL_ALIGN 4
#ifdef USE_ITHREADS
# define SIG_PENDING_OFFSET 0x10		/* my_perl->Isig_pending offset */
# include "i386thr.c"
#else
# include "i386.c"
#endif
#endif

/* __amd64 defines __x86_64 */
#if (defined(__x86_64__) || defined(__amd64)) 
#define CALL_ALIGN 0
#define JIT_CPU "amd64"
#ifdef USE_ITHREADS
# define SIG_PENDING_OFFSET 0x10 		/* my_perl->Isig_pending offset */
# include "amd64thr.c"
#else
# include "amd64.c"
#endif
#endif

#ifndef JIT_CPU
#error "Only intel supported so far"
#endif



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
    int line = 3;
    FILE *fh, *stabs;
    char *opname;
#endif
    unsigned int rel;
    unsigned char *code, *code_sav;
#ifndef USE_ITHREADS
    void* PL_op_ptr = &PL_op;
#endif

    /* quirky pass 1: need code size to allocate string.
       PL_slab_count should be near the optree size.
       Need to time that against an realloc checker in pass 2.
     */
#ifdef DEBUGGING
    fh = fopen("run-jit.c", "a");
    fprintf(fh, "void runops_jit_%d (void);\nvoid runops_jit_%d (void){\n", 
            global_loops, global_loops);
#endif
    OP * root = PL_op;
    int size = 0;
    size += sizeof(PROLOG);
    do {
#ifdef DEBUGGING
        opname = PL_op_name[PL_op->op_type];
        printf("#pp_%s \t= 0x%x\n",opname,PL_op->op_ppaddr);
#endif
	if (PL_op->op_type == OP_NULL) continue;
	size += sizeof(CALL);
	size += sizeof(void*);
#if CALL_ALIGN
	while ((size | 0xfffffff0) % CALL_ALIGN) { size++; }
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
    PL_op = root;
#ifdef _WIN32
    code = VirtualAlloc(NULL, size,
			MEM_COMMIT | MEM_RESERVE,
			PAGE_EXECUTE_READWRITE);
#else
    code = (char*)malloc(size);
#endif
    code_sav = code;

#ifdef DEBUGGING
    stabs = fopen("run-jit.s", "a");
    /* filename info */
    fprintf(stabs, ".data\n.text\n");       /* darwin wants it */
    fprintf(stabs, ".file  \"run-jit.c\"\n");
    fprintf(stabs, ".stabs \"%s\",100,0,0,0\n", "run-jit.c");   /* filename */
    /* jit_func start addr */
    fprintf(stabs, ".stabs \"runops_jit_%d:F(0,1)\",36,0,2,%p\n", global_loops, code); 
    fprintf(stabs, ".stabs \"Void:t(0,0)=(0,1)\",128,0,0,0\n"); /* stack variables */
#  if INTVAL_SIZE == 4
    fprintf(stabs, ".stabs \"INTVAL:t(0,1)=(0,5)\",128,0,0,0\n");
#  else
    fprintf(stabs, ".stabs \"INTVAL:t(0,1)=(0,7)\",128,0,0,0\n");
#  endif
    fprintf(stabs, ".stabs \"Ptr:t(0,2)=*(0,0)\",128,0,0,0\n");
    fprintf(stabs, ".stabs \"CharPtr:t(0,3)=*(0,1)\",128,0,0,0\n");
    fprintf(stabs, ".stabs \"STRING:t(0,4)=*(0,5)\",128,0,0,0\n");
    fprintf(stabs, ".stabs \"struct op:t(0,5)=*(0,6)\",128,0,0,0\n");
# ifdef USE_ITHREADS
    fprintf(stabs, ".stabs \"PerlInterpreter:S(0,12)\",38,0,0,%p\n", /* variable in data section */
            (char*)&my_perl);
# endif
    fprintf(stabs, ".stabn 68,0,1,0\n");
    /*
    fprintf(stabs, ".def	_Perl_pp_enter;	.scl	2;	.type	32;	.endef\n");
    fprintf(stabs, ".def	_Perl_pp_nextstate;	.scl	2;	.type	32;	.endef\n");
    fprintf(stabs, ".def	_Perl_pp_print;	.scl	2;	.type	32;	.endef\n");
    fprintf(stabs, ".def	_Perl_pp_leave;	.scl	2;	.type	32;	.endef\n");
    fprintf(stabs, ".def	_Perl_Isig_pending_ptr;	.scl	2;	.type	32;	.endef\n");
    fprintf(stabs, ".def	_Perl_despatch_signals;	.scl	2;	.type	32;	.endef\n");
    fprintf(stabs, ".def	_pthread_getspecific;	.scl	2;	.type	32;	.endef\n");
    fprintf(stabs, ".def	_Perl_Gthr_key_ptr;	.scl	2;	.type	32;	.endef\n");
    */
    global_loops++;
#endif

#define PUSHc(what) memcpy(code,what,sizeof(what)); code += sizeof(what)

    /* pass 2: jit */
    PUSHc(PROLOG);
    do {
	if (PL_op->op_type == OP_NULL) continue;
	/* relative offset to addr */
#ifdef DEBUGGING
        opname = PL_op_name[PL_op->op_type];
        fprintf(stabs, ".stabn 68,0,%d,%d /* call pp_%s */\n", 
                line, code-code_sav, opname);
# ifdef USE_ITHREADS
        fprintf(fh, "my_perl->Iop = Perl_pp_%s(my_perl);\n", opname);
# else
        fprintf(fh, "PL_op = Perl_pp_%s();\n", opname);
# endif
#endif
        rel = (unsigned char*)PL_op->op_ppaddr - (code+1) - sizeof(void*);
#ifdef USE_ITHREADS
        rel -= 3;
#endif
        if (rel > (unsigned int)1<<31) {
	    PUSHc(JMP);
	    PUSHc(&PL_op->op_ppaddr);
        } else {
	    PUSHc(CALL);
	    PUSHc(&rel);
        }
	/* 386 calls prefer 2 nop's afterwards, align it to 4 (0,4,8,c)*/
#if CALL_ALIGN
	while (((unsigned int)&code | 0xfffffff0) % CALL_ALIGN) { *(code++) = NOP[0]; }
#endif
#ifdef DEBUGGING
        fprintf(stabs, ".stabn 68,0,%d,%d /* PL_op = eax */\n",
                line++, code-code_sav);
#endif
	PUSHc(SAVE_PLOP);
#ifndef USE_ITHREADS
	PUSHc(&PL_op_ptr);
#endif
	if (DISPATCH_NEEDED(PL_op)) {
#ifdef DEBUGGING
# ifdef USE_ITHREADS
            fprintf(fh, "if (my_perl->Isig_pending)\n  Perl_despatch_signals(my_perl);\n");
# else
            fprintf(fh, "if (PL_sig_pending)\n  Perl_despatch_signals();\n");
# endif
            fprintf(stabs, ".stabn 68,0,%d,%d /* if (PL_sig_pending) */\n",
                    line++, code-code_sav);
#endif
#if !defined(USE_ITHREADS) && PERL_VERSION > 6
	    PUSHc(DISPATCH_GETSIG);
	    PUSHc(&PL_sig_pending);
#endif
#ifdef DEBUGGING
            fprintf(stabs, ".stabn 68,0,%d,%d /* Perl_despatch_signals() */\n",
                    line++, code-code_sav);
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
    fprintf(fh, "}\n");
    fclose(fh);
    fprintf(stabs, ".stabs \"\",36,0,1,%p\n", (char *)size); /* eof */
    /* for stabs: as run-jit.s; gdb file run-jit.o */
    fclose(stabs);
    system("as run-jit.s -o run-jit.o");

    printf("#Perl_despatch_signals \t= 0x%x\n",Perl_despatch_signals);
# if !defined(USE_ITHREADS) && PERL_VERSION > 6
    printf("#PL_sig_pending \t= 0x%x\n",&PL_sig_pending);
# endif
#endif
    /*I_ASSERT(size == (code - c));*/
    /*size = code - c;*/

    PL_op = root;
    code = code_sav;
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
#ifdef DEBUGGING
    unlink("run-jit.c");
    unlink("run-jit.s");
    unlink("run-jit.o");
#endif
#ifdef JIT_CPU
    sv_setsv(get_sv("Jit::CPU", GV_ADD), newSVpv(JIT_CPU, 0)); 
    PL_runops = Perl_runops_jit;
#endif
