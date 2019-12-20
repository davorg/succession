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

my $app_date;

sub order_by_succession {
  my $self = shift;
  ($app_date) = @_;
  $app_date //= DateTime->today;

  return sort succession_sort $self->all;
}

sub succession_sort {
  my $succession_change_enact  = DateTime->new(
    year => 2015, month =>  3, day => 26,
  );
  my $succession_change_cutoff = DateTime->new(
    year => 2011, month => 10, day => 28,
  );

  if ($app_date < $succession_change_enact) {
    return ($b->sex cmp $a->sex or $a->born <=> $b->born);
  }

  if ($a->gender ne $b->gender) {
    if ($a->gender eq 'm') {
      if ($a->born < $succession_change_cutoff) {
        return -1;
      } else {
        return $a->born <=> $b->born;
      }
    } else {
      if ($b->born < $succession_change_cutoff) {
        return 1;
      } else {
        return $a->born <=> $b->born;
      }
    }
  } else {
     return $a->born <=> $b->born;
  }
}

__PACKAGE__->meta->make_immutable;

1;
