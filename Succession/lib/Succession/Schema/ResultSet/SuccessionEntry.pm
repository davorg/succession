package Succession::Schema::ResultSet::SuccessionEntry;

use strict;
use warnings;
use experimental 'signatures';

use parent 'DBIx::Class::ResultSet';

sub order_by_date($self) {
  return $self->search(
    {},
    {
      join     => 'period',
      order_by => 'period.from_date',
      prefetch => 'period',
    }
  );
}

sub collapsed_by_position($self) {
  my @collapsed;
  my $current;

  my $entries = $self->order_by_date;

  while (my $entry = $entries->next) {
    if (!$current) {
      $current = {
        position => $entry->position,
        start    => $entry->start,
        end      => $entry->end,
      };
      next;
    }

    my $same_position = $current->{position} == $entry->position;
    my $adjacent      = (
      defined $current->{end}
      && defined $entry->start
      && $current->{end}->ymd eq $entry->start->ymd
    );

    if ($same_position && $adjacent) {
      $current->{end} = $entry->end;
      next;
    }

    push @collapsed, $current;
    $current = {
      position => $entry->position,
      start    => $entry->start,
      end      => $entry->end,
    };
  }

  push @collapsed, $current if $current;

  return \@collapsed;
}

1;
