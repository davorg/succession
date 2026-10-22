use strict;
use warnings;

BEGIN { $ENV{SUCC_CACHE_DRIVER} = 'Null' }

use CHI;
use DateTime;
use Test::More;

use Succession::App;
use Succession::Model;
use Succession::Schema;

sub date {
  my ($year, $month, $day) = split /-/, $_[0];
  return DateTime->new(year => $year, month => $month, day => $day);
}

my $schema = Succession::Schema->connect('dbi:SQLite:dbname=:memory:', '', '', {
  quote_names => 1, on_connect_do => 'PRAGMA foreign_keys = ON',
});
$schema->deploy;

my @people;
for my $name ('King', 'Queen', 'Excluded', 'Prince') {
  my $person = $schema->resultset('Person')->create({
    born => '1950-01-01', sex => 'f', slug => lc $name,
  });
  $person->add_to_titles({ title => $name, is_default => 1 });
  push @people, $person;
}
my ($king, $queen, $excluded, $prince) = @people;
$excluded->add_to_exclusions({ reason => 'c' });
$schema->resultset('Sovereign')->populate([
  { person_id => $king->id, start => '2000-01-01', end => '2000-02-01' },
  { person_id => $queen->id, start => '2000-02-01' },
]);
for my $case (
  [ '2000-01-01', '2000-02-01', [$queen, $excluded, $prince] ],
  [ '2000-02-01', undef, [$excluded, $prince] ],
) {
  my ($from, $to, $people) = @$case;
  my $period = $schema->resultset('SuccessionPeriod')->create({ from_date => $from, to_date => $to });
  my ($rank, $order) = (0, 0);
  for my $person (@$people) {
    my $position = $person->id == $excluded->id ? undef : ++$rank;
    $period->add_to_display_entries({
      person_id => $person->id, display_order => ++$order, succession_rank => $position,
    });
    $period->add_to_succession_entries({ person_id => $person->id, rank => $position })
      if defined $position;
  }
}

my $model = Succession::Model->new(schema => $schema, cache => CHI->new(driver => 'Null'));

for my $case (
  [ '2000-01-31', $king, [$queen->id, $prince->id] ],
  [ '2000-02-01', $queen, [$prince->id] ],
) {
  my ($day, $sovereign, $eligible_ids) = @$case;
  my $dt = date($day);
  is($model->sovereign_on_date($dt)->person_id, $sovereign->id,
    "$day selects the correct sovereign at an accession boundary");
  is_deeply([map { $_->id } @{ $model->succession_on_date($dt) }], $eligible_ids,
    "$day returns eligible successors in rank order");
  my $display = $model->succession_display_on_date($dt);
  my ($excluded_row) = grep { $_->{person}->id == $excluded->id } @$display;
  is($excluded_row->{exclusion_reason}, 'Catholic', "$day retains the dated exclusion for display");
  ok(!defined $excluded_row->{rank}, "$day gives the excluded person no succession rank");
}

my $before = date('1999-12-31');
ok(!defined $model->sovereign_on_date($before), 'date before the first reign returns no sovereign');
is_deeply($model->succession_on_date($before), [], 'date before stored periods returns an empty succession');

my $data = $model->get_succession_data(date('2000-01-31'), 1);
is($data->{date}, '2000-01-31', 'structured data uses the explicit date');
is($data->{sovereign}{name}, 'King', 'structured data contains the dated sovereign');
is_deeply([map { $_->{name} } @{ $data->{successors} }], ['Queen'],
  'structured data honours the successor limit and excludes ineligible people');
my $app = Succession::App->new(model => $model);
is_deeply($app->get_succession_data(date('2000-01-31'), 1), $data,
  'App retains its working structured-data delegation');

for my $method (qw(sovereign_on_date succession_on_date succession_display_on_date)) {
  for my $case (
    ['omitted', []], ['undefined', [undef]], ['string', ['2000-01-31']], ['unblessed reference', [{}]],
  ) {
    my ($label, $args) = @$case;
    eval { $model->$method(@$args) };
    like($@, qr/\Q$method\E\(\) requires a DateTime object/,
      "$method rejects date input ($label) with a clear requirement");
  }
}

ok(!Succession::Model->can('get_succession'), 'Model no longer exposes the broken name-only API');
ok(!Succession::App->can('get_succession'), 'App no longer delegates the broken API');

done_testing();
