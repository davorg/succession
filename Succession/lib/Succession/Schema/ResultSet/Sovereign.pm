package Succession::Schema::ResultSet::Sovereign;

use Moose;
use MooseX::NonMoose;

extends 'DBIx::Class::ResultSet';

sub BUILDARGS { $_[2] }

sub sovereign_on_date {
  my $self = shift;
  my ($date) = @_;

  $date = $self->result_source->schema->storage->
          datetime_parser->format_datetime($date);

  return $self->find({
    start => { '<=' => $date },
    end   => [ { '>' => $date }, undef ],
  }, {
    prefetch => qw[person],
  });
}

sub anniversaries {
  my $self = shift;

  my @anniversaries = $self->search(
    \[
      q{
        ( DATE_FORMAT(start, '%m-%d')
            BETWEEN DATE_FORMAT(CURDATE(), '%m-%d')
            AND     DATE_FORMAT(DATE_ADD(CURDATE(), INTERVAL 7 DAY), '%m-%d') )
        OR
        ( DATE_FORMAT(CURDATE(), '%m-%d')
            > DATE_FORMAT(DATE_ADD(CURDATE(), INTERVAL 7 DAY), '%m-%d')
          AND (
            DATE_FORMAT(start, '%m-%d') >= DATE_FORMAT(CURDATE(), '%m-%d')
            OR  DATE_FORMAT(start, '%m-%d')
              <= DATE_FORMAT(DATE_ADD(CURDATE(), INTERVAL 7 DAY), '%m-%d')
          )
        )
      }
    ],
    {
      order_by => {
        -asc => [
          \ "MONTH(start)",
          \ "DAY(start)",
          \ "YEAR(start)",
        ],
      },
    },
  );

  return \@anniversaries;
}

__PACKAGE__->meta->make_immutable;

1;
