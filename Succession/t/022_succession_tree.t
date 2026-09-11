use strict;
use warnings;

use Test::More;
use DateTime;

use Succession::Model;

my $model = Succession::Model->new;
my $date = DateTime->today;
my $current_sovereign = $model->sovereign_on_date($date);

my $tree = $model->succession_tree($current_sovereign->id, $date);

is(ref $tree, 'HASH', 'succession_tree returns a hashref root node');
is($tree->{name}, $current_sovereign->person->name_on_date($date), 'root node is the chosen sovereign');
ok(!defined $tree->{succession_number}, 'root sovereign has no succession number');

my @succession_numbers;
check_node($tree, $date, 1);

ok(@succession_numbers, 'tree contains at least one living descendant with succession number');

my %seen;
for my $num (@succession_numbers) {
  like($num, qr/\A[1-9]\d*\z/, 'succession_number is a positive integer');
  ok(!$seen{$num}++, 'succession_number values are unique');
}

if (!defined $current_sovereign->person->died) {
  my $before_reign = $current_sovereign->start->clone->subtract(days => 1);

  my $ok = eval {
    $model->succession_tree($current_sovereign->id, $before_reign);
    1;
  };
  ok(!$ok, 'living sovereign is rejected when not current on the date');
  like($@, qr/current on date or be dead/, 'invalid sovereign/date combination has expected error');
} else {
  pass('Current sovereign is dead; skipping non-current living sovereign validation');
}

my ($dead_sovereign) = $model->sovereign_rs->search({
  'me.id'      => { '!=' => $current_sovereign->id },
  'person.died' => { '!=' => undef },
}, {
  join => 'person',
  order_by => { -desc => 'me.end' },
  rows => 1,
});

if ($dead_sovereign) {
  my $ok = eval {
    $model->succession_tree($dead_sovereign->id, $date);
    1;
  };
  ok($ok, 'dead (past) sovereign is accepted');
} else {
  pass('No dead sovereign found in fixture data');
}

my ($former_living_sovereign) = $model->sovereign_rs->search({
  'me.end'      => { '!=' => undef },
  'person.died' => { '>'  => \'me.end' },
}, {
  join => 'person',
  order_by => { -asc => 'me.end' },
  rows => 1,
});

if ($former_living_sovereign) {
  my $probe_date = $former_living_sovereign->end->clone->add(days => 1);
  my $ok = eval {
    $model->succession_tree($former_living_sovereign->id, $probe_date);
    1;
  };
  ok(!$ok, 'former sovereign is rejected when they are not dead on target date');
  like($@, qr/current on date or be dead/, 'former still-living sovereign has expected error');
} else {
  pass('No former still-living sovereign found in fixture data');
  pass('No former still-living sovereign found in fixture data');
}

done_testing();

sub check_node {
  my ($node, $date, $is_root) = @_;

  for my $required (qw[name born age alive_on_date children]) {
    ok(exists $node->{$required}, "node contains $required");
  }

  cmp_ok($node->{born}, 'le', $date->ymd, 'node was born on or before target date');
  is(ref $node->{children}, 'ARRAY', 'children is an arrayref');
  ok($node->{alive_on_date} == 0 || $node->{alive_on_date} == 1, 'alive_on_date is 0 or 1');

  if (!$node->{alive_on_date}) {
    ok(!defined $node->{succession_number}, 'dead person has no succession number');
  } elsif (!$is_root) {
    ok(defined $node->{succession_number}, 'living descendant has succession number');
    push @succession_numbers, $node->{succession_number};
  }

  my @child_births = map { $_->{born} } @{ $node->{children} };
  is_deeply(\@child_births, [ sort @child_births ], 'children are ordered oldest first');

  for my $child (@{ $node->{children} }) {
    check_node($child, $date, 0);
  }
}
