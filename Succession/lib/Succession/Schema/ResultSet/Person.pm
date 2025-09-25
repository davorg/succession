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

sub birthdays {
  my $self = shift;

  my @birthdays = $self->search(
    \[
      q{
        ( DATE_FORMAT(born, '%m-%d') BETWEEN DATE_FORMAT(CURDATE(), '%m-%d')
                                       AND DATE_FORMAT(DATE_ADD(CURDATE(), INTERVAL 7 DAY), '%m-%d') )
        OR
        (
          DATE_FORMAT(CURDATE(), '%m-%d') > DATE_FORMAT(DATE_ADD(CURDATE(), INTERVAL 7 DAY), '%m-%d')
          AND (
            DATE_FORMAT(born, '%m-%d') >= DATE_FORMAT(CURDATE(), '%m-%d')
            OR  DATE_FORMAT(born, '%m-%d') <= DATE_FORMAT(DATE_ADD(CURDATE(), INTERVAL 7 DAY), '%m-%d')
          )
        )
      }
    ],
    {
      order_by => {
        -asc => [
          \ "MONTH(born)",
          \ "DAY(born)",
          \ "YEAR(born)",
        ],
      },
    },
  );

  return \@birthdays;
}

__PACKAGE__->meta->make_immutable;

1;
