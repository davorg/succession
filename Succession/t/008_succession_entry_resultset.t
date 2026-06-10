use strict;
use warnings;

use Test::More;

use Succession::Schema;

my $schema = Succession::Schema->get_schema;

my $person_with_adjacent_duplicate_position;

PERSON:
for my $person ($schema->resultset('Person')->search(
  {},
  {
    join     => 'succession_entries',
    distinct => 1,
  }
)->all) {
  my @entries = $person->succession_entries_rs->order_by_date->all;
  next unless @entries > 1;

  for my $i (1 .. $#entries) {
    if ($entries[$i - 1]->position == $entries[$i]->position) {
      $person_with_adjacent_duplicate_position = $person;
      last PERSON;
    }
  }
}

if (!$person_with_adjacent_duplicate_position) {
  plan skip_all => 'No person with adjacent duplicate succession positions in fixture data';
}

my @entries   = $person_with_adjacent_duplicate_position->succession_entries_rs->order_by_date->all;
my $collapsed = $person_with_adjacent_duplicate_position->succession_entries_rs->collapsed_by_position;

is(ref $collapsed, 'ARRAY', 'collapsed_by_position returns an array ref');
ok(@$collapsed < @entries, 'Collapsed ranges are fewer than raw entries');

for my $i (1 .. $#$collapsed) {
  isnt(
    $collapsed->[$i - 1]{position},
    $collapsed->[$i]{position},
    'No adjacent duplicate positions remain after collapsing',
  );
}

is(
  $collapsed->[0]{position},
  $entries[0]->position,
  'First collapsed position matches first raw entry',
);
is(
  $collapsed->[0]{start}->ymd,
  $entries[0]->start->ymd,
  'First collapsed start date matches first raw entry',
);

is(
  ($collapsed->[-1]{end} ? $collapsed->[-1]{end}->ymd : ''),
  ($entries[-1]->end    ? $entries[-1]->end->ymd      : ''),
  'Last collapsed end date matches last raw entry',
);

done_testing();
