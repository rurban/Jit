# i386 unthreaded sample runloop
        .file	"3-jit-hand_32_nt.S"
	.text
	.p2align 4,,15
.globl _runops_jit_0
	.def	_runops_jit_0;	.scl	2;	.type	32;	.endef

# PL_op in eax, &PL_op in ebx, &PL_sig_pending in -4(%ebp), local op in (%esp)
_runops_jit_0:
prolog:
	enter   $8,$0
        pushl 	%ebx
        pushl 	%edx
#	pushl	%ecx
        # movl    0x8(%ebp),%ebx ; threaded:      Iop is at 8 from my_perl
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
        mov    %eax, (%ebx)
        call   _Perl_pp_gt
        mov    %eax, (%ebx)
        movl   $_op, 0(%esp) 	#  op = PL_op->op_next
        call   _Perl_pp_entersub
        mov    %eax, (%ebx)
        test   %eax, %eax        	#  if (!PL_op) return;
        je     sub_1_next
        pop    %edx
        pop    %ebx
        leave
        ret
sub_1_next:      
        cmp    %eax,(%esp)		#  if (PL_op != op) call (PL_op->op_ppaddr)();
        je     sub_1_end
        add    $8, %eax			# +op_ppaddr offset
        call   *%eax			# call sub dynamically (unjitted)
        mov    %eax, (%ebx)		# save_plop
sub_1_end:           
	call	_Perl_pp_padsv
	movl	_PL_op, %eax
	movl	%eax, -8(%ebp)
	movl	$_PL_op, (%esp)
	call	_Perl_pp_cond_expr
	movl	%eax, (%ebx)
check_sig2:        
	movl	-4(%ebp), %edx
	movl	(%edx), %eax
	testl	%eax, %eax
	je	L3
	call	_Perl_despatch_signals
# compare returned PL_op against prev op->op_next in %ecx        
L3:
	mov	_PL_op, %eax
	cmp	%eax, (%esp)
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
	jmp     0x0010
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
        
#	popl	%ecx
        popl 	%edx
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
        
	.comm	_op, 4, 2
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
