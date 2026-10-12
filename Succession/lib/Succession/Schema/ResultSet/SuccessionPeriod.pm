package Succession::Schema::ResultSet::SuccessionPeriod;

use strict;
use warnings;
use experimental 'signatures';

use parent 'DBIx::Class::ResultSet';

sub succession_on_date {
  my ($self, $date) = @_;

  die "succession_on_date() requires a date" unless defined $date;

  $date = $date->ymd;

  my $row = $self->search(
    {
      'me.from_date' => { '<=' => $date },
      -or            => [
        'me.to_date' => undef,
        'me.to_date' => { '>' => $date },
      ],
    },
    {
      order_by => [
        { -desc => 'me.from_date' },   # latest applicable period
        'display_entries.display_order',
      ],
      rows     => 1,
      prefetch => {
        display_entries => {
          person => [ qw(titles exclusions) ],
        },
      },
    },
  )->first;

  return $row;
}

1;
