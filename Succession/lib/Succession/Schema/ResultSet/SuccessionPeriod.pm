package Succession::Schema::ResultSet::SuccessionPeriod;

use strict;
use warnings;
use experimental 'signatures';

use parent 'DBIx::Class::ResultSet';

sub succession_on_date {
  my ($self, $date) = @_;

  die "succession_on_date() requires a date" unless defined $date;

  $date = $self->result_source->schema->storage
            ->datetime_parser->format_datetime($date);

  my $row = $self->search(
    {
      'me.from_date' => { '<=' => $date },
      -or            => [
        'me.to_date' => undef,
        'me.to_date' => { '>' => $date },
      ],
    },
    {
      order_by => { -desc => 'me.from_date' },   # latest applicable period
      rows     => 1,
      prefetch => {
        succession_entries => 'person',
      },
    },
  )->first;

  return $row;
}

1;
