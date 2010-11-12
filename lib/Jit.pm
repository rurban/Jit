#      perl5 runloop jit
#
#      Copyright (c) 2010 Reini Urban
#
#      You may distribute under the terms of either the GNU General Public
#      License or the Artistic License, as specified in the README file.
#
#      Assemble into a mprotected string and call into it instead of the runloop

package Jit;
our $VERSION = '0.0402';
require DynaLoader;
use vars qw( @ISA $VERSION );
@ISA = qw(DynaLoader);

Jit->bootstrap($VERSION);

=pod

=head1 NAME

Jit the perl5 runops loop in proper execution order

=head1 DESCRIPTION

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
