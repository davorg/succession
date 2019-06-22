package Succession::Schema::ResultSet::Exclusion;

use Moose;
use MooseX::NonMoose;

extends 'DBIx::Class::ResultSet';

sub BUILDARGS { $_[2] }

sub order_by_date {
  my $self = shift;

  return $self->search(undef, { order_by => 'start' });
}

__PACKAGE__->meta->make_immutable;

1;
