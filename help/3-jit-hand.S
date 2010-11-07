	.file	"3-jit-hand.S"
	.text
	.p2align 4,,15
.globl _runops_jit_0
	.def	_runops_jit_0;	.scl	2;	.type	32;	.endef

# PL_op in eax, &PL_op in ebx, &PL_sig_pending in -4(%ebp), local op in -8(%ebp)
_runops_jit_0:
prolog:
	pushl	%ebp
	movl	%esp, %ebp
        pushl 	%ebx
	pushl	%ecx
	subl	$8, %esp
	movl	$_PL_op, %ebx
	movl	$_Perl_Isig_pending_ptr, -4(%ebp)
loop:           
	call	_Perl_pp_enter
	movl	%eax, (%ebx)
	call	_Perl_pp_nextstate
	movl	%eax, (%ebx)
	call	_Perl_pp_const
	movl	%eax, (%ebx)
	call	_Perl_pp_padsv
	movl	%eax, (%ebx)
	call	_Perl_pp_sassign
	movl	%eax, (%ebx)
	call	_Perl_pp_nextstate
	movl	%eax, (%ebx)
check_sig1:
	movl	-4(%ebp), %edx
	movl	(%edx), %eax
	testl	%eax, %eax
	je	L2
	call	_Perl_despatch_signals
L2:
	call	_Perl_pp_padsv
	movl	%eax, (%ebx)
	call	_Perl_pp_const
	movl	%eax, (%ebx)
	call	_Perl_pp_gt
	movl	%eax, (%ebx)
maybranch1:
	movl	_PL_op, %eax
	movl	%eax, -8(%ebp)
	call	_Perl_pp_cond_expr
	movl	%eax, (%ebx)
check_sig2:        
	movl	-4(%ebp), %edx
	movl	(%edx), %eax
	testl	%eax, %eax
	je	L3
	call	_Perl_despatch_signals
L3:
	movl	_PL_op, %eax
	cmpl	-8(%ebp), %eax
	je	next_1
        
# op_other block from if (if true)
other_1:
	call	_Perl_pp_pushmark
	movl	%eax, (%ebx)
	call	_Perl_pp_const
	movl	%eax, (%ebx)
	call	_Perl_pp_print
	movl	%eax, (%ebx)
	jmp	leave_1
        
# op_next block from if (if false)
next_1:
	call	_Perl_pp_enter
	movl	%eax, (%ebx)
	call	_Perl_pp_nextstate
	movl	%eax, (%ebx)
check_sig3:        
	movl	-4(%ebp), %edx
	movl	(%edx), %eax
	testl	%eax, %eax
	je	L7
	call	_Perl_despatch_signals
L7:
	call	_Perl_pp_leave
	movl	%eax, (%ebx)
leave_1:
	call	_Perl_pp_leave
	movl	%eax, (%ebx)
        
	popl	%ecx
        popl	%ebx
	leave
	ret

	.def	___main;	.scl	2;	.type	32;	.endef
.globl _main
	.def	_main;	.scl	2;	.type	32;	.endef
_main:
	leal	4(%esp), %ecx
	andl	$-16, %esp
	pushl	-4(%ecx)
	pushl	%ebp
	movl	%esp, %ebp
	pushl	%ecx
	subl	$4, %esp
	call	___main
	call	_runops_jit_0
	addl	$4, %esp
	popl	%ecx
	popl	%ebp
	leal	-4(%ecx), %esp
	ret
        
	.comm	_PL_op, 4, 2
	.comm	_Perl_Isig_pending_ptr, 4, 2
	.def	_Perl_pp_sassign;	.scl	2;	.type	32;	.endef
	.def	_Perl_pp_padsv;	.scl	2;	.type	32;	.endef
	.def	_Perl_pp_gt;	.scl	2;	.type	32;	.endef
	.def	_Perl_pp_cond_expr;	.scl	2;	.type	32;	.endef
	.def	_Perl_pp_pushmark;	.scl	2;	.type	32;	.endef
	.def	_Perl_pp_const;	.scl	2;	.type	32;	.endef
	.def	_Perl_pp_print;	.scl	2;	.type	32;	.endef
	.def	_Perl_pp_enter;	.scl	2;	.type	32;	.endef
	.def	_Perl_pp_nextstate;	.scl	2;	.type	32;	.endef
	.def	_Perl_despatch_signals;	.scl	2;	.type	32;	.endef
	.def	_Perl_pp_leave;	.scl	2;	.type	32;	.endef
