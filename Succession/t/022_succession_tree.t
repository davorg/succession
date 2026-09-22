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
is($tree->{current_sovereign}, 1, 'root node is flagged when it is the current sovereign');

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
    push @succession_numbers, $node->{succession_number}
      if defined $node->{succession_number};
  }

  my @child_births = map { $_->{born} } @{ $node->{children} };
  is_deeply(\@child_births, [ sort @child_births ], 'children are ordered oldest first');

  for my $child (@{ $node->{children} }) {
    check_node($child, $date, 0);
  }
}

my $corner_date = DateTime->new(year => 1962, month => 9, day => 7);
my $george_v_sov = $model->sovereign_rs->find({
  start => '1910-05-06',
  end   => '1936-01-20',
});

ok($george_v_sov, 'Found sovereign row for George V reign dates');

if ($george_v_sov) {
  my $corner_tree = $model->succession_tree($george_v_sov->id, $corner_date);
  my $edward_node = find_node_by_born($corner_tree, '1894-06-23');
  my $elizabeth_node = find_node_by_born($corner_tree, '1926-04-21');

  ok($edward_node, 'Edward VIII node exists in George V tree');
  if ($edward_node) {
    is($edward_node->{alive_on_date}, 1, 'Edward VIII is alive on 1962-09-07');
    ok(!defined $edward_node->{succession_number}, 'Edward VIII has no succession number after his reign');
    ok(defined $edward_node->{exclusion_reason}, 'Edward VIII has an exclusion_reason');
  }

  ok($elizabeth_node, 'Elizabeth II node exists in George V tree');
  if ($elizabeth_node) {
    is($elizabeth_node->{current_sovereign}, 1, 'current sovereign on date is flagged in tree');
  }
}

sub find_node_by_born {
  my ($node, $born) = @_;

  return $node if $node->{born} eq $born;

  for my $child (@{ $node->{children} }) {
    my $found = find_node_by_born($child, $born);
    return $found if $found;
  }

  return;
}

my $modern_date = DateTime->new(year => 2025, month => 9, day => 7);
my $modern_tree = $model->succession_tree(1, $modern_date, 'birth');
my $arthur = find_node_by_born($modern_tree, '1999-02-05');
is($arthur->{succession_number}, 31, 'Arthur Chatto is numbered beyond the stored top 30');
my $full_tree = $model->succession_tree(4, $modern_date, 'succession');
is(find_node_by_born($full_tree, '1944-08-26')->{succession_number}, 32,
  'later family branches also receive full succession numbers');

my $ordering_tree = { children => [
  { name => 'excluded', children => [] },
  { name => 'later branch', children => [
    { name => 'later successor', succession_number => 8, children => [] },
  ] },
  { name => 'dead leaf', children => [] },
  { name => 'earlier ancestor', children => [
    { name => 'second', succession_number => 2, children => [] },
    { name => 'first', succession_number => 1, children => [] },
  ] },
  { name => 'sovereign branch', children => [
    { name => 'sovereign', current_sovereign => 1, children => [] },
  ] },
] };
$model->_order_succession_tree($ordering_tree);
is_deeply([map { $_->{name} } @{$ordering_tree->{children}}],
  ['excluded', 'sovereign branch', 'dead leaf', 'earlier ancestor', 'later branch'],
  'whole branches follow descendant ranks while unranked branches keep their slots');
is_deeply([map { $_->{name} } @{$ordering_tree->{children}[3]{children}}],
  ['first', 'second'], 'ordering applies recursively');
my $invalid = eval { $model->succession_tree(4, $corner_date, 'unknown'); 1 };
ok(!$invalid, 'model rejects unsupported ordering');
like($@, qr/Order must be birth or succession/, 'model reports ordering error');

done_testing();
