use strict;
use warnings;
BEGIN { $ENV{SUCC_CACHE_DRIVER} = 'Null' }

use CHI;
use DateTime;
use HTTP::Request::Common;
use JSON::MaybeXS qw(decode_json encode_json);
use Plack::Test;
use Test::More;
use Succession;
use Succession::Model;
use Succession::Schema;
use Succession::Snapshot;

sub date {
  my ($year, $month, $day) = split /-/, $_[0];
  return DateTime->new(year => $year, month => $month, day => $day);
}

my $schema = Succession::Schema->connect('dbi:SQLite:dbname=:memory:', '', '', {
  quote_names => 1, on_connect_do => 'PRAGMA foreign_keys = ON',
});
$schema->deploy;
my $root = $schema->resultset('Person')->create({ born => '1800-01-01', sex => 'm', slug => 'root-king' });
$root->add_to_titles({ title => 'Fixture King', is_default => 1 });
$schema->resultset('Sovereign')->create({ person_id => $root->id, start => '2000-01-01', image => 'fixture-king' });

my %children;
for my $order (1 .. 35) {
  my $p = $schema->resultset('Person')->create({
    born => '1900-01-01', sex => 'f', parent => $root->id,
    family_order => $order, slug => "child-$order",
    died => $order == 2 ? '2000-01-05' : undef,
  });
  $p->add_to_titles({ title => "Child $order", is_default => 1 });
  $children{$order} = $p;
}
$children{1}->add_to_exclusions({ reason => 'c' });
$children{17}->add_to_exclusions({ reason => 'mc', start => '2000-01-03', end => '2000-01-07' });
$children{31}->add_to_exclusions({ reason => 'i' });
$children{34}->add_to_exclusions({ reason => 'c' });
my $grandchild = $schema->resultset('Person')->create({
  born => '2000-01-04', sex => 'm', parent => $children{17}->id,
  family_order => 1, slug => 'grandchild-test',
});
$grandchild->add_to_titles({ title => 'Grandchild', is_default => 1 });

my $generator = Succession::Snapshot->new(schema => $schema, earliest => '2000-01-01');
my $rows = $generator->line_on_date('2000-01-03');
is(scalar(@$rows), 33, 'three exclusions add three rows to thirty eligible successors');
is_deeply([ map { $_->{succession_rank} } grep { defined $_->{succession_rank} } @$rows ],
  [ 1 .. 30 ], 'eligible ranks remain contiguous');
is($rows->[0]{person_id}, $children{1}->id, 'excluded first child retains family position');
ok(!defined($rows->[0]{succession_rank}), 'excluded first child has no rank');
is($rows->[1]{succession_rank}, 1, 'first eligible child is rank one');
ok(!(grep { $_->{person_id} == $grandchild->id } @$rows), 'future birth is absent');
ok(!(grep { $_->{person_id} == $children{34}->id } @$rows), 'exclusion after the cutoff is absent');

my $after_birth = $generator->line_on_date('2000-01-04');
my ($child) = grep { $_->{person_id} == $grandchild->id } @$after_birth;
ok(defined($child->{succession_rank}), 'eligible descendant of excluded parent retains a rank');
my ($parent) = grep { $_->{person_id} == $children{17}->id } @$after_birth;
ok(!defined($parent->{succession_rank}), 'parent is still excluded on the birth date');
is($after_birth->[$parent->{display_order}]{person_id}, $grandchild->id,
  'descendant remains directly after its excluded parent');
ok(!(grep { $_->{person_id} == $children{2}->id } @{ $generator->line_on_date('2000-01-05') }),
  'death takes effect on the death date');
my ($before_end) = grep { $_->{person_id} == $children{17}->id } @{ $generator->line_on_date('2000-01-06') };
my ($on_end) = grep { $_->{person_id} == $children{17}->id } @{ $generator->line_on_date('2000-01-07') };
ok(!defined($before_end->{succession_rank}), 'exclusion remains active before its end');
ok(defined($on_end->{succession_rank}), 'exclusion ends on its end date');

my $plan = $generator->plan('2000-01-10');
is_deeply([ map { $_->{date} } @{ $plan->{periods} } ],
  [ qw(2000-01-01 2000-01-03 2000-01-04 2000-01-05 2000-01-07) ],
  'births, deaths, exclusion starts and exclusion ends create boundaries');
$generator->apply($plan);
my $death_period = $schema->resultset('SuccessionPeriod')->find({ from_date => '2000-01-05' });
is($death_period->change_type, 'death', 'death period has the correct event metadata');
is($death_period->change_position, 1, 'death records the rank immediately before removal');
my $again = Succession::Snapshot->new(schema => $schema, earliest => '2000-01-01')->plan('2000-01-10');
is(scalar(@{ $again->{differences} }), 0, 'rebuilding does not change the ranked lists again');
is(scalar(grep { !$_->{existing} } @{ $again->{periods} }), 0, 'rebuilding adds no duplicate periods');
is_deeply($again->{obsolete}, [], 'rebuilding removes no further boundaries');

sub contents {
  return encode_json($schema->storage->dbh->selectall_arrayref(
    'SELECT period_id, display_order, person_id, succession_rank FROM succession_display_entry ORDER BY period_id, display_order'));
}
my $before = contents();
$again->{periods}[-1]{rows}[-1]{person_id} = 999999;
eval { $generator->apply($again) };
like($@, qr/FOREIGN KEY constraint failed/, 'invalid rebuild fails');
is(contents(), $before, 'failed rebuild rolls back replacement of all display rows');

my $model = Succession::Model->new(schema => $schema, cache => CHI->new(driver => 'Null'));
my $display = $model->succession_display_on_date(date('2000-01-03'));
is_deeply([ map { $_->{exclusion_reason} } grep { !defined $_->{rank} } @$display ],
  [ 'Catholic', 'Married a Catholic', 'Illegitimate' ], 'display rows have readable dated reasons');
is(scalar(@{ $model->succession_on_date(date('2000-01-03')) }), 30, 'model API returns eligible people only');
is(scalar(@{ $model->get_succession_data(date('2000-01-03'), 30)->{successors} }), 30,
  'MCP data contains thirty eligible successors');

{
  no warnings qw(redefine once);
  local *Succession::Schema::get_schema = sub { $schema };
  local $DBIx::Class::ResultSourceHandle::thaw_schema = $schema;
  local *Succession::Model::get_feed_entries = sub { [] };
  local *DateTime::today = sub { date('2000-01-03') };
  my $test = Plack::Test->create(Succession->to_app);
  for my $path ('/', '/2000-01-03') {
    my $res = $test->request(GET $path);
    ok($res->is_success, "$path renders with exclusions");
    my $html = $res->decoded_content;
    my ($list) = $html =~ m{<ul class="succession-list">(.*?)</ul>}s;
    is(scalar(() = $list =~ /<li\b/g), 33, 'renders all thirty-three display rows');
    is(scalar(() = $list =~ /class="excluded"/g), 3, 'three exclusions are styled separately');
    is(scalar(() = $list =~ /class="succession-number">X\./g), 3, 'three exclusions show X');
    like($list, qr{Excluded: Married a Catholic}, 'exclusion description is visible');
    unlike($html, qr{We don't have thirty}, 'complete eligible list has no warning');
    my ($json) = $html =~ m{<script type="application/ld\+json">(.*?)</script>}s;
    my $items = decode_json($json)->{itemListElement};
    is(scalar(@$items), 31, 'JSON-LD includes sovereign and thirty eligible people');
    ok(!(grep { $_->{item}{name} eq 'Child 1' || $_->{item}{name} eq 'Child 17'
      || $_->{item}{name} eq 'Child 31' } @$items), 'JSON-LD excludes ineligible people');
  }

  # A genuinely smaller family must still warn, even if exclusions inflate
  # the number of visible rows beyond thirty.
  $schema->resultset('SuccessionEntry')->search({ rank => { '>' => 29 } })->delete;
  $schema->resultset('SuccessionDisplayEntry')->search({ succession_rank => { '>' => 29 } })->delete;
  my $res = $test->request(GET '/2000-01-03');
  like($res->decoded_content, qr{We don't have thirty}, 'twenty-nine eligible people still trigger the warning');
}

my $before_invalid_graph = contents();
$root->update({ parent => $grandchild->id, family_order => 1 });
eval { Succession::Snapshot->new(schema => $schema) };
like($@, qr/Cycle in genealogy/, 'cyclic source data is rejected before rebuilding');
is(contents(), $before_invalid_graph, 'invalid genealogy does not replace existing snapshots');

done_testing();
