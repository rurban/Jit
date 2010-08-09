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
#define STACK_SPACE 0x08   /* private area. Mostly used for cheap stack alignment */

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

#define CALL_SIZE  4				/* size for the call instruction arg */
#define MOV_SIZE   4				/* size for the mov instruction arg */
#ifdef USE_ITHREADS
# define SIG_PENDING_OFFSET 0x10		/* my_perl->Isig_pending offset */
#endif

#if (defined(__i386__) || defined(_M_IX86))
#define JIT_CPU "i386"
#define JIT_CPU_TYPE 1
#define CALL_ALIGN 4
#undef  MOV_REL
#ifdef USE_ITHREADS
# include "i386thr.c"
#else
# include "i386.c"
#endif
#endif

/* __amd64 defines __x86_64 */
#if (defined(__x86_64__) || defined(__amd64)) 
#define JIT_CPU "amd64"
#define JIT_CPU_TYPE 2
#define CALL_ALIGN 0
#define MOV_REL
#ifdef USE_ITHREADS
# include "amd64thr.c"
#else
# include "amd64.c"
#endif
#endif

#ifndef JIT_CPU
#error "Only intel x86_32 and x86_64/amd64 supported so far"
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
    static int global_loops = 0;
    static int line = 0;
    register int i;
    FILE *fh;
    char *opname;
#if defined(DEBUGGING) && defined(__GCC__)
    FILE *stabs;
#endif
#endif
    U32 rel; /* 4 byte int */
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
    line += 2;
#endif
    OP * root = PL_op;
    int size = 0;
    size += sizeof(PROLOG);
    do {
#ifdef DEBUGGING
        opname = PL_op_name[PL_op->op_type];
        DEBUG_v( printf("#pp_%s \t= 0x%x\n",opname,PL_op->op_ppaddr));
#endif
	if (PL_op->op_type == OP_NULL) continue;
	size += sizeof(CALL);
	size += CALL_SIZE;
#if CALL_ALIGN
	while ((size | 0xfffffff0) % CALL_ALIGN) { size++; }
#endif
	size += sizeof(SAVE_PLOP);
#ifndef USE_ITHREADS
	size += MOV_SIZE;
#endif
	if (DISPATCH_NEEDED(PL_op)) {
#ifndef USE_ITHREADS
	    size += sizeof(DISPATCH_GETSIG);
	    size += MOV_SIZE;
#endif
	    size += sizeof(DISPATCH);
	    size += MOV_SIZE;
#ifdef USE_ITHREADS
	    size += sizeof(DISPATCH_POST);
#endif
	}
    } while (PL_op = PL_op->op_next);
    size += sizeof(EPILOG);
    while ((size | 0xfffffff0) % 4) { size++; }
    PL_op = root;
#ifdef _WIN32
    code = VirtualAlloc(NULL, size,
			MEM_COMMIT | MEM_RESERVE,
			PAGE_EXECUTE_READWRITE);
#else
    /* memalign and getpagesize certainly need a Makefile.PL/configure check */
    code = (char*)memalign(getpagesize(), size*sizeof(char));
    /* amd64/linux disallows mprotect'ing an unaligned heap. 
       We NEED to start it in a fresh new page. */
    /*code = (char*)malloc(size);*/
#endif
    code_sav = code;

#if defined(DEBUGGING) && defined(__GCC__)
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
            (char*)&my_perl);
# endif
    fprintf(stabs, ".stabn 68,0,1,0\n");
    global_loops++;
#endif

#define PUSHc(what) memcpy(code,what,sizeof(what)); code += sizeof(what)
/* force 4 byte for U32, 64bit uses 8 byte for U32 */ 
#define PUSHcall(what) memcpy(code,what,CALL_SIZE); code += CALL_SIZE
#ifdef MOV_REL
# define PUSHmov(where) { \
    U32 r = (unsigned char*)where - (code+4); \
    memcpy(code,&r,MOV_SIZE); code += MOV_SIZE; \
} 
#else
# define PUSHmov(what) memcpy(code,what,MOV_SIZE); code += MOV_SIZE
#endif

    /* pass 2: jit */
    PUSHc(PROLOG);
    do {
	if (PL_op->op_type == OP_NULL) continue;
	/* relative offset to addr */
#ifdef DEBUGGING
        opname = PL_op_name[PL_op->op_type];
# if defined(DEBUGGING) && defined(__GCC__)
        fprintf(stabs, ".stabn 68,0,%d,%d /* call pp_%s */\n", 
                line, code-code_sav, opname);
# endif
# ifdef USE_ITHREADS
        fprintf(fh, "my_perl->Iop = Perl_pp_%s(my_perl);\n", opname);
# else
        fprintf(fh, "PL_op = Perl_pp_%s();\n", opname);
# endif
#endif
        rel = (unsigned char*)PL_op->op_ppaddr - (code+1) - 4;
        if (rel > (unsigned int)PERL_ULONG_MAX) {
	    PUSHc(JMP);
	    PUSHcall(&PL_op->op_ppaddr);
	    /* 386 far calls prefer 2 nop's afterwards, align it to 4 (0,4,8,c)*/
#if CALL_ALIGN
	    while (((unsigned int)&code | 0xfffffff0) % CALL_ALIGN) { *(code++) = NOP[0]; }
#endif
        } else {
	    PUSHc(CALL);
	    PUSHcall(&rel);
        }
#if defined(DEBUGGING) && defined(__GCC__)
        fprintf(stabs, ".stabn 68,0,%d,%d /* PL_op = eax */\n",
                line++, code-code_sav);
#endif
	PUSHc(SAVE_PLOP);
#ifndef USE_ITHREADS
	PUSHmov(&PL_op); /* was PL_op_ptr on i386 */ 
#endif
	if (DISPATCH_NEEDED(PL_op)) {
#ifdef DEBUGGING
# ifdef USE_ITHREADS
            fprintf(fh, "if (my_perl->Isig_pending)\n  Perl_despatch_signals(my_perl);\n");
# else
            fprintf(fh, "if (PL_sig_pending)\n  Perl_despatch_signals();\n");
# endif
# if defined(DEBUGGING) && defined(__GCC__)
            fprintf(stabs, ".stabn 68,0,%d,%d /* if (PL_sig_pending) */\n",
                    line++, code-code_sav);
# endif
#endif
#if !defined(USE_ITHREADS) && PERL_VERSION > 6
	    PUSHc(DISPATCH_GETSIG);
	    PUSHmov(&PL_sig_pending);
#endif
#if defined(DEBUGGING) && defined(__GCC__)
            fprintf(stabs, ".stabn 68,0,%d,%d /* Perl_despatch_signals() */\n",
                    line++, code-code_sav);
#endif
	    PUSHc(DISPATCH);
	    PUSHmov(&Perl_despatch_signals);
#ifdef USE_ITHREADS
	    PUSHc(DISPATCH_POST);
#endif
	}
    } while (PL_op = PL_op->op_next);
    PUSHc(EPILOG);
    while (((unsigned int)&code | 0xfffffff0) % 4) { *(code++) = NOP[0]; }

#ifdef DEBUGGING
    fprintf(fh, "}\n");
    line++;
    fclose(fh);
# if defined(DEBUGGING) && defined(__GCC__)
    fprintf(stabs, ".stabs \"\",36,0,1,%p\n", (char *)size); /* eof */
    /* for stabs: as run-jit.s; gdb add-symbol-file run-jit.o 0 */
    fclose(stabs);
    system("as run-jit.s -o run-jit.o");
# endif
    DEBUG_v( printf("#Perl_despatch_signals \t= 0x%x\n",Perl_despatch_signals) );
# if !defined(USE_ITHREADS) && PERL_VERSION > 6
    DEBUG_v( printf("#PL_sig_pending \t= 0x%x\n",&PL_sig_pending) );
# endif
#endif
    /*I_ASSERT(size == (code - code_sav));*/
    /*size = code - code_sav;*/

    PL_op = root;
    code = code_sav;
#ifdef HAS_MPROTECT
    if (mprotect(code,size*sizeof(char),PROT_EXEC|PROT_READ) < 0)
      croak ("mprotect failed");
#endif
    /* XXX Missing. Prepare for execution: flush CPU cache. Needed only on ppc32 and ppc64 */

    /* gdb: disassemble code code+200 */
#ifdef DEBUGGING
    DEBUG_v( printf("#PL_op    \t= 0x%x\n",&PL_op) );
    DEBUG_v( printf("#code()=0x%x size=%d",code,size) );
    for (i=0; i < size; i++) {
      if (!(i % 8)) DEBUG_v( printf("\n#") );
      DEBUG_v( printf("%02x ",code[i]) );
    }
    DEBUG_v( printf("\n#run-jit:\n") );
#endif

    (*((void (*)(pTHX))code))(aTHX);

    TAINT_NOT;
#ifdef _WIN32
    VirtualFree(code, 0, MEM_RELEASE);
#else
    free(code);
#endif
    return 0;
}

MODULE=Jit 	PACKAGE=Jit

PROTOTYPES: DISABLE

BOOT:
#ifdef DEBUGGING
    unlink("run-jit.c");
# if defined(DEBUGGING) && defined(__GCC__)
    unlink("run-jit.s");
    unlink("run-jit.o");
# endif
#endif
#ifdef JIT_CPU
    sv_setsv(get_sv("Jit::CPU", GV_ADD), newSVpv(JIT_CPU, 0)); 
    PL_runops = Perl_runops_jit;
#endif
