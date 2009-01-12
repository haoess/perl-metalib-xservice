package MetaLib::XService::Error;

use warnings;
use strict;

=head1 METHODS

=head2 new

=cut

sub new {
    my ($class, $args) = @_;
    my $self = bless {} => $class;
    $self->{code}    = $args->{code};
    $self->{content} = $args->{content};
    $self->{msg}     = $args->{msg};
    $self->{type}    = $args->{type};
    return $self;
}

=head2 code

=cut

sub code { shift->{code} }

=head2 content

=cut

sub content { shift->{content} }

=head2 msg

=cut

sub msg { shift->{msg} }

=head2 type

=cut

sub type { shift->{type} }

1;
