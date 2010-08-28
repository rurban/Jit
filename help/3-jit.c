typedef struct op OP; struct op {OP* op_next};
OP *PL_op; int *Perl_Isig_pending_ptr; void runops_jit_0 (void);
void runops_jit_0 (void){
    register OP* op; 
    register int *plop = &PL_op;
    register int *p = &Perl_Isig_pending_ptr;
    PL_op = Perl_pp_enter();
    PL_op = Perl_pp_nextstate();
    PL_op = Perl_pp_const();
    PL_op = Perl_pp_padsv();
    PL_op = Perl_pp_sassign();
    PL_op = Perl_pp_nextstate();
    if (*p)
        Perl_despatch_signals();
    PL_op = Perl_pp_padsv();
    PL_op = Perl_pp_const();
    PL_op = Perl_pp_gt();

 maybranch_1:
    op = PL_op->op_next;
    PL_op = Perl_pp_cond_expr();
    if (*p)
        Perl_despatch_signals();
    if (PL_op == op) /* false */
        goto next_1;
 other_1:
    PL_op = Perl_pp_pushmark();
    PL_op = Perl_pp_const();
    PL_op = Perl_pp_print();
    goto leave_1; /* upper scope */

 next_1:
    PL_op = Perl_pp_enter();
    PL_op = Perl_pp_nextstate();
    if (*p)
        Perl_despatch_signals();
    PL_op = Perl_pp_leave();
 leave_1:
    PL_op = Perl_pp_leave();
    return;
}

int main() {
    runops_jit_0();
}

/* unthreaded i386:
gcc -fstack-protector 3-jit.c /usr/lib/perl5/5.10/i686-cygwin/CORE/libperl.a -lcrypt 
objdump -d a.exe > 3-jit.exedis-static

00401130 <_runops_jit_0>:
  401130:	55                   	push   %ebp
  401131:	89 e5                	mov    %esp,%ebp
  401133:	83 ec 08             	sub    $0x8,%esp
  401136:	c7 45 fc d0 90 50 00 	movl   $0x5090d0,-0x4(%ebp)
  40113d:	e8 ce 11 00 00       	call   402310 <_Perl_pp_enter>
  401142:	a3 c0 75 54 00       	mov    %eax,0x5475c0
  401147:	e8 24 31 00 00       	call   404270 <_Perl_pp_nextstate>
  40114c:	a3 c0 75 54 00       	mov    %eax,0x5475c0
  401151:	e8 aa a1 00 00       	call   40b300 <_Perl_pp_const>
  401156:	a3 c0 75 54 00       	mov    %eax,0x5475c0
  40115b:	e8 f0 96 00 00       	call   40a850 <_Perl_pp_padsv>
  401160:	a3 c0 75 54 00       	mov    %eax,0x5475c0
  401165:	e8 86 9d 00 00       	call   40aef0 <_Perl_pp_sassign>
  40116a:	a3 c0 75 54 00       	mov    %eax,0x5475c0
  40116f:	e8 fc 30 00 00       	call   404270 <_Perl_pp_nextstate>
  401174:	a3 c0 75 54 00       	mov    %eax,0x5475c0
  401179:	8b 55 fc             	mov    -0x4(%ebp),%edx
  40117c:	8b 02                	mov    (%edx),%eax
  40117e:	85 c0                	test   %eax,%eax
  401180:	74 05                	je     401187 <_runops_jit_0+0x57> 182+05=187
  401182:	e8 19 b8 01 00       	call   41c9a0 <_Perl_despatch_signals>
  401187:	e8 c4 96 00 00       	call   40a850 <_Perl_pp_padsv>
  40118c:	a3 c0 75 54 00       	mov    %eax,0x5475c0
  401191:	e8 6a a1 00 00       	call   40b300 <_Perl_pp_const>
  401196:	a3 c0 75 54 00       	mov    %eax,0x5475c0
  40119b:	e8 f0 3a 01 00       	call   414c90 <_Perl_pp_gt>
  4011a0:	a3 c0 75 54 00       	mov    %eax,0x5475c0
  4011a5:	a1 c0 75 54 00       	mov    0x5475c0,%eax
  4011aa:	89 45 f8             	mov    %eax,-0x8(%ebp)
  4011ad:	e8 ce 31 00 00       	call   404380 <_Perl_pp_cond_expr>
  4011b2:	a3 c0 75 54 00       	mov    %eax,0x5475c0
  4011b7:	8b 55 fc             	mov    -0x4(%ebp),%edx
  4011ba:	8b 02                	mov    (%edx),%eax
  4011bc:	85 c0                	test   %eax,%eax
  4011be:	74 05                	je     4011c5 <_runops_jit_0+0x95> 1c0+05=1c5
  4011c0:	e8 db b7 01 00       	call   41c9a0 <_Perl_despatch_signals>
  4011c5:	a1 c0 75 54 00       	mov    0x5475c0,%eax
  4011ca:	3b 45 f8             	cmp    -0x8(%ebp),%eax
  4011cd:	74 20                	je     4011ef <_runops_jit_0+0xbf>
  4011cf:	e8 4c 57 00 00       	call   406920 <_Perl_pp_pushmark>
  4011d4:	a3 c0 75 54 00       	mov    %eax,0x5475c0
  4011d9:	e8 22 a1 00 00       	call   40b300 <_Perl_pp_const>
  4011de:	a3 c0 75 54 00       	mov    %eax,0x5475c0
  4011e3:	e8 38 86 00 00       	call   409820 <_Perl_pp_print>
  4011e8:	a3 c0 75 54 00       	mov    %eax,0x5475c0
  4011ed:	eb 2c                	jmp    40121b <_runops_jit_0+0xeb> 1ef+2c=21b
  4011ef:	e8 1c 11 00 00       	call   402310 <_Perl_pp_enter>
  4011f4:	a3 c0 75 54 00       	mov    %eax,0x5475c0
  4011f9:	e8 72 30 00 00       	call   404270 <_Perl_pp_nextstate>
  4011fe:	a3 c0 75 54 00       	mov    %eax,0x5475c0
  401203:	8b 55 fc             	mov    -0x4(%ebp),%edx
  401206:	8b 02                	mov    (%edx),%eax
  401208:	85 c0                	test   %eax,%eax
  40120a:	74 05                	je     401211 <_runops_jit_0+0xe1>
  40120c:	e8 8f b7 01 00       	call   41c9a0 <_Perl_despatch_signals>
  401211:	e8 4a 1b 00 00       	call   402d60 <_Perl_pp_leave>
  401216:	a3 c0 75 54 00       	mov    %eax,0x5475c0
  40121b:	e8 40 1b 00 00       	call   402d60 <_Perl_pp_leave>
  401220:	a3 c0 75 54 00       	mov    %eax,0x5475c0
  401225:	c9                   	leave  
  401226:	c3                   	ret    

amd64:
gcc -fstack-protector 3-jit.c /usr/lib/perl5/5.13.3/i686-nothreads-debug-linux/CORE/libperl.a -lcrypt -lm
objdump -d a.out > 3-jit.exedis-static64

0000000000404fd4 <runops_jit_0>:
  404fd4:	55                   	push   %rbp
  404fd5:	48 89 e5             	mov    %rsp,%rbp
  404fd8:	41 54                	push   %r12
  404fda:	53                   	push   %rbx
  404fdb:	bb 10 61 9d 00       	mov    $0x9d6110,%ebx
  404fe0:	b8 00 00 00 00       	mov    $0x0,%eax
  404fe5:	e8 86 a7 03 00       	callq  43f770 <Perl_pp_enter>
  404fea:	48 98                	cltq   
  404fec:	48 89 05 15 11 5d 00 	mov    %rax,0x5d1115(%rip)        # 9d6108 <PL_op>
  404ff3:	b8 00 00 00 00       	mov    $0x0,%eax
  404ff8:	e8 f9 89 02 00       	callq  42d9f6 <Perl_pp_nextstate>
  404ffd:	48 98                	cltq   
  404fff:	48 89 05 02 11 5d 00 	mov    %rax,0x5d1102(%rip)        # 9d6108 <PL_op>
  405006:	b8 00 00 00 00       	mov    $0x0,%eax
  40500b:	e8 6c 89 02 00       	callq  42d97c <Perl_pp_const>
  405010:	48 98                	cltq   
  405012:	48 89 05 ef 10 5d 00 	mov    %rax,0x5d10ef(%rip)        # 9d6108 <PL_op>
  405019:	b8 00 00 00 00       	mov    $0x0,%eax
  40501e:	e8 98 bd 02 00       	callq  430dbb <Perl_pp_padsv>
  405023:	48 98                	cltq   
  405025:	48 89 05 dc 10 5d 00 	mov    %rax,0x5d10dc(%rip)        # 9d6108 <PL_op>
  40502c:	b8 00 00 00 00       	mov    $0x0,%eax
  405031:	e8 2d 93 02 00       	callq  42e363 <Perl_pp_sassign>
  405036:	48 98                	cltq   
  405038:	48 89 05 c9 10 5d 00 	mov    %rax,0x5d10c9(%rip)        # 9d6108 <PL_op>
  40503f:	b8 00 00 00 00       	mov    $0x0,%eax
  405044:	e8 ad 89 02 00       	callq  42d9f6 <Perl_pp_nextstate>
  405049:	48 98                	cltq   
  40504b:	48 89 05 b6 10 5d 00 	mov    %rax,0x5d10b6(%rip)        # 9d6108 <PL_op>
  405052:	8b 03                	mov    (%rbx),%eax
  405054:	85 c0                	test   %eax,%eax
  405056:	74 0a                	je     405062 <runops_jit_0+0x8e>
  405058:	b8 00 00 00 00       	mov    $0x0,%eax
  40505d:	e8 a4 6f 00 00       	callq  40c006 <Perl_despatch_signals>
  405062:	b8 00 00 00 00       	mov    $0x0,%eax
  405067:	e8 4f bd 02 00       	callq  430dbb <Perl_pp_padsv>
  40506c:	48 98                	cltq   
  40506e:	48 89 05 93 10 5d 00 	mov    %rax,0x5d1093(%rip)        # 9d6108 <PL_op>
  405075:	b8 00 00 00 00       	mov    $0x0,%eax
  40507a:	e8 fd 88 02 00       	callq  42d97c <Perl_pp_const>
  40507f:	48 98                	cltq   
  405081:	48 89 05 80 10 5d 00 	mov    %rax,0x5d1080(%rip)        # 9d6108 <PL_op>
  405088:	b8 00 00 00 00       	mov    $0x0,%eax
  40508d:	e8 d0 7c 0b 00       	callq  4bcd62 <Perl_pp_gt>
  405092:	48 98                	cltq   
  405094:	48 89 05 6d 10 5d 00 	mov    %rax,0x5d106d(%rip)        # 9d6108 <PL_op>
  40509b:	48 8b 05 66 10 5d 00 	mov    0x5d1066(%rip),%rax        # 9d6108 <PL_op>
  4050a2:	4c 8b 20             	mov    (%rax),%r12
  4050a5:	b8 00 00 00 00       	mov    $0x0,%eax
  4050aa:	e8 38 a7 02 00       	callq  42f7e7 <Perl_pp_cond_expr>
  4050af:	48 98                	cltq   
  4050b1:	48 89 05 50 10 5d 00 	mov    %rax,0x5d1050(%rip)        # 9d6108 <PL_op>
  4050b8:	8b 03                	mov    (%rbx),%eax
  4050ba:	85 c0                	test   %eax,%eax
  4050bc:	74 0a                	je     4050c8 <runops_jit_0+0xf4>
  4050be:	b8 00 00 00 00       	mov    $0x0,%eax
  4050c3:	e8 3e 6f 00 00       	callq  40c006 <Perl_despatch_signals>
  4050c8:	48 8b 05 39 10 5d 00 	mov    0x5d1039(%rip),%rax        # 9d6108 <PL_op>
  4050cf:	4c 39 e0             	cmp    %r12,%rax
  4050d2:	74 3b                	je     40510f <runops_jit_0+0x13b>
  4050d4:	b8 00 00 00 00       	mov    $0x0,%eax
  4050d9:	e8 70 8c 02 00       	callq  42dd4e <Perl_pp_pushmark>
  4050de:	48 98                	cltq   
  4050e0:	48 89 05 21 10 5d 00 	mov    %rax,0x5d1021(%rip)        # 9d6108 <PL_op>
  4050e7:	b8 00 00 00 00       	mov    $0x0,%eax
  4050ec:	e8 8b 88 02 00       	callq  42d97c <Perl_pp_const>
  4050f1:	48 98                	cltq   
  4050f3:	48 89 05 0e 10 5d 00 	mov    %rax,0x5d100e(%rip)        # 9d6108 <PL_op>
  4050fa:	b8 00 00 00 00       	mov    $0x0,%eax
  4050ff:	e8 36 08 03 00       	callq  43593a <Perl_pp_print>
  405104:	48 98                	cltq   
  405106:	48 89 05 fb 0f 5d 00 	mov    %rax,0x5d0ffb(%rip)        # 9d6108 <PL_op>
  40510d:	eb 4a                	jmp    405159 <runops_jit_0+0x185> # leave_1
  40510f:	90                   	nop
  405110:	b8 00 00 00 00       	mov    $0x0,%eax
  405115:	e8 56 a6 03 00       	callq  43f770 <Perl_pp_enter>
  40511a:	48 98                	cltq   
  40511c:	48 89 05 e5 0f 5d 00 	mov    %rax,0x5d0fe5(%rip)        # 9d6108 <PL_op>
  405123:	b8 00 00 00 00       	mov    $0x0,%eax
  405128:	e8 c9 88 02 00       	callq  42d9f6 <Perl_pp_nextstate>
  40512d:	48 98                	cltq   
  40512f:	48 89 05 d2 0f 5d 00 	mov    %rax,0x5d0fd2(%rip)        # 9d6108 <PL_op>
  405136:	8b 03                	mov    (%rbx),%eax
  405138:	85 c0                	test   %eax,%eax
  40513a:	74 0a                	je     405146 <runops_jit_0+0x172>
  40513c:	b8 00 00 00 00       	mov    $0x0,%eax
  405141:	e8 c0 6e 00 00       	callq  40c006 <Perl_despatch_signals>
  405146:	b8 00 00 00 00       	mov    $0x0,%eax
  40514b:	e8 f3 b0 03 00       	callq  440243 <Perl_pp_leave>
  405150:	48 98                	cltq   
  405152:	48 89 05 af 0f 5d 00 	mov    %rax,0x5d0faf(%rip)        # 9d6108 <PL_op>
leave_1:
  405159:	b8 00 00 00 00       	mov    $0x0,%eax
  40515e:	e8 e0 b0 03 00       	callq  440243 <Perl_pp_leave>
  405163:	48 98                	cltq   
  405165:	48 89 05 9c 0f 5d 00 	mov    %rax,0x5d0f9c(%rip)        # 9d6108 <PL_op>
  40516c:	5b                   	pop    %rbx
  40516d:	41 5c                	pop    %r12
  40516f:	c9                   	leaveq 
  405170:	c3                   	retq   


*/
