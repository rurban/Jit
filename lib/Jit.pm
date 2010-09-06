#      perl5 runloop jit
#
#      Copyright (c) 2010 Reini Urban
#
#      You may distribute under the terms of either the GNU General Public
#      License or the Artistic License, as specified in the README file.
#
#      Assemble into a mprotected string and call into it instead of the runloop

package Jit;
our $VERSION = '0.0302';
require DynaLoader;
use vars qw( @ISA $VERSION );
@ISA = qw(DynaLoader);

Jit->bootstrap($VERSION);

=head NAME

Jit the perl5 runops loop in proper execution order

=head DESCRIPTION

It does only work yet for non-threaded simple functions! No subs, no branches.

This perl5 jitter is super-simple. The compiled optree is a linked
list in memory in non-execution order, wide-spread jumps. Additionally
the calls are indirect. The jitter properly aligns the run-time calls
in linear linked-list "exec" order, so that the CPU can prefetch the
next instructions.

The old indirect call far costs about 70 cycles,
the new direct call near costs 3-5 cycles and is cached.

Speed up:
  TODO

Additional memory costs:
  TODO

=cut

1;
