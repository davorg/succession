package Succession::Schema::ResultSet::Person;

use Moose;
use MooseX::NonMoose;

extends 'DBIx::Class::ResultSet';

sub BUILDARGS { $_[2] }

sub order_by_age {
  my $self = shift;

  return $self->search(undef, { order_by => 'born' });
}

sub find_by_slug {
  my $self = shift;
  my ($slug) = @_;

  $slug =~ s/-.*//;

  return $self->find({
    slug => { like => "$slug-%" },
  });
}

__PACKAGE__->meta->make_immutable;

1;
