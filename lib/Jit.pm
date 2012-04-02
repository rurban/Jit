#      perl5 runloop jit
#
#      Copyright (c) 2010,2012 Reini Urban
#
#      You may distribute under the terms of either the GNU General Public
#      License or the Artistic License, as specified in the README file.
#
#      Assemble into a mprotected string and call into it instead of the runloop

package Jit;
our $VERSION = '0.05';
require DynaLoader;
use vars qw( @ISA $VERSION );
@ISA = qw(DynaLoader);
my (%only, %ignore);

Jit->bootstrap($VERSION);

# optional args: package names, sub names, regex?
sub import {
  shift;
  if (@_) {
    warn "use Jit names... not yet implemented\n";
    for (@_) { $Jit::only{$_} = 1; }
  } else {
    $^H |= $Jit::HINT_JIT_FLAGS;
  }
}

sub unimport {
  shift;
  if (@_) {
    warn "no Jit names... not yet implemented\n";
    for (@_) { $Jit::ignore{$_} = 1; }
  } else {
    $^H &= ~ $Jit::HINT_JIT_FLAGS;
    warn "{ no Jit; ... } lexical-scope jitting not yet implemented\n";
  }
}

=pod

=head1 NAME

Jit the perl5 runops loop in proper execution order

=head1 SYNOPSIS

  perl -MJit ...
    or
  use Jit; # jit most functions

planned:

  use Jit qw(My this::sub);     # jit some packages or subs only
  no Jit qw(My::OtherPackage other::sub);  # but do not jit some other packages or subs

  {
    use Jit; # jit only this block
    ...
  }

  {
    no Jit; # do not Jit this block
    ...
  }

=head1 DESCRIPTION

This perl5 jitter is super-simple.

WARNING: It does only work yet for simple functions! No non-local jumps.
Only Intel CPU's 32 and 64bit, i386 and amd64.

The original compiled optree from the perl5 parser is a linked list in memory in
non-execution order, with wide-spread jumps, almost in reverse order.
Additionally the calls are indirect, and with a shared libperl even far, which
is stops the CPU prefetching.

This Jit module properly aligns the run-time calls in linear "exec" order,
so that the CPU can prefetch the next (and other) instructions.
The old indirect far call within a shared libperl costs about 70 cycles,
the new direct call near costs 3-5 cycles and enables CPU prefetching.

Speed up:
  See http://blogs.perl.org/users/rurban/2010/11/performance-hacks.html

Additional memory costs:
  2-10 byte per op

=head1 AUTHOR

Reini Urban C<perl-compiler@googlegroups.com> written from scratch.

=head1 LICENSE

Copyright (c) 2010 Reini Urban

You may distribute under the terms of either the GNU General Public
License or the Artistic License, as specified in the README file.

=cut

1;
