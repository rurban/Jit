#      perl5 runloop jit
#
#      Copyright (c) 2010 Reini Urban
#
#      You may distribute under the terms of either the GNU General Public
#      License or the Artistic License, as specified in the README file.
#
#      Assemble into a mprotected string and call into it instead of the runloop

package Jit;
our $VERSION = '0.04_09';
require DynaLoader;
use vars qw( @ISA $VERSION );
@ISA = qw(DynaLoader);

Jit->bootstrap($VERSION);

=pod

=head1 NAME

Jit the perl5 runops loop in proper execution order

=head1 DESCRIPTION

WARNING: It does only work yet for simple functions! No branches, no non-local jumps.
Only intel CPU's 32 and 64bit (i386 and amd64).

This perl5 jitter is super-simple.

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
