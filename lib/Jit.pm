#      perl5 runloop jit
#
#      Copyright (c) 2010 Reini Urban
#
#      You may distribute under the terms of either the GNU General Public
#      License or the Artistic License, as specified in the README file.
#
#      Assemble into a mprotected string and call into it instead of the runloop

package Jit;
our $VERSION = '0.01';
require DynaLoader;
use vars qw( @ISA $VERSION );
@ISA = qw(DynaLoader);

Jit->bootstrap($VERSION);

=head NAME

Jit the perl5 runops loop in proper execution order

=head DESCRIPTION

IT DOES NOT WORK YET!

This perl5 jitter is super-simple. The compiled optree is a linked
list in memory in non-execution order, wide-spread jumps. Additionally
the calls are indirect.  The jitter properly aligns the run-time calls
in linear linked-list "exec" order, so that the CPU can prefetch the
next instructions.

=cut

1;
