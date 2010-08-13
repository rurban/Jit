typedef struct op OP; struct op {OP* op_next};
OP *PL_op; int *Perl_Isig_pending_ptr; void runops_jit_0 (void);
void runops_jit_0 (void){
    register OP* op; register int *p = &Perl_Isig_pending_ptr;
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

    op = PL_op;
    PL_op = Perl_pp_cond_expr();
    if (*p)
        Perl_despatch_signals();
    if (PL_op == op)
        goto next_1;
 other_1:
    PL_op = Perl_pp_pushmark();
    PL_op = Perl_pp_const();
    PL_op = Perl_pp_print();
    goto leave_1;

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
 
*/
