#      perl5 runloop jit
#
#      Copyright (c) 2010 Reini Urban
#
#      You may distribute under the terms of either the GNU General Public
#      License or the Artistic License, as specified in the README file.
#
#      Assemble into a mprotected string and call into it instead of the runloop

package Jit;
our $VERSION = '0.04';
require DynaLoader;
use vars qw( @ISA $VERSION );
@ISA = qw(DynaLoader);

Jit->bootstrap($VERSION);

=head NAME

Jit the perl5 runloop in proper execution order and near calls.

=head DESCRIPTION

It does only work yet for simple functions! No subs, no branches.
Only intel (i386 and amd64) yet.

This perl5 jitter is super-simple. The compiled optree from
the perl5 parser is a linked list in memory in non-execution
order, with wide-spread jumps, almost in reverse order.

Additionally the calls are indirect.

The jitter properly aligns the run-time calls in linear "exec" order, so that
the CPU can prefetch the next (and other) instructions.

The old indirect call far costs about 70 cycles,
the new direct call near costs 3-5 cycles and is cached.

Speed up:
  TODO

Additional memory costs:
  TODO

=head1 AUTHOR

Reini Urban C<perl-compiler@googlegroups.com> written from scratch.

=head1 LICENSE

Copyright (c) 2010 Reini Urban

You may distribute under the terms of either the GNU General Public
License or the Artistic License, as specified in the README file.

=cut

1;
