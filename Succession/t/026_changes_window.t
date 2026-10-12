use strict;
use warnings;

BEGIN { $ENV{SUCC_CACHE_DRIVER} = 'Null' }

use CHI;
use DateTime;
use HTTP::Request::Common;
use Plack::Test;
use Test::More;

use Succession;
use Succession::Model;
use Succession::Schema;

{
  package Local::ChangesWindowQueryCounter;

  use parent 'DBIx::Class::Storage::Statistics';

  sub query_start {
    my ($self, $sql) = @_;
    push @{ $self->{queries} }, $sql;
  }

  sub query_end { }

  sub queries { $_[0]->{queries} // [] }
}

my $schema = Succession::Schema->connect('dbi:SQLite:dbname=:memory:', '', '', {
  quote_names => 1,
});
$schema->deploy;

my $event_date = DateTime->new(year => 2000, month => 12, day => 31);
my $change_date = $schema->resultset('ChangeDate')->create({
  change_date => $event_date->ymd,
});

for my $event (
  [ 'New child', 'was born' ],
  [ 'Former successor', 'died' ],
) {
  my $person = $schema->resultset('Person')->create({
    born => '1900-01-01',
    sex  => 'm',
  });
  $person->add_to_titles({ title => $event->[0], is_default => 1 });
  $change_date->add_to_changes({
    person_id   => $person->id,
    description => $event->[1],
  });
}

my $cache = CHI->new(driver => 'Memory', datastore => {});
$cache->set('changes_around|' . $event_date->ymd, []);
my $model = Succession::Model->new(schema => $schema, cache => $cache);

for my $offset (-3 .. 3) {
  my $date = $event_date->clone->add(days => $offset);
  my $original = $date->ymd;
  my $changes = $model->get_changes_on_date($date);
  is_deeply(
    [ map { $_->change_date->ymd } @$changes ],
    abs($offset) <= 2 ? [ $event_date->ymd ] : [],
    "offset $offset uses the inclusive two-day window across a year boundary",
  );
  is($date->ymd, $original, 'lookup does not change the supplied date');
}

my $counter = Local::ChangesWindowQueryCounter->new;
$schema->storage->debugobj($counter);
$schema->storage->debug(1);

my $uncached_model = Succession::Model->new(
  schema => $schema,
  cache  => CHI->new(driver => 'Null'),
);
my $changes = $uncached_model->get_changes_on_date($event_date);
my @events = map {
  [ $_->person->name, $_->description ]
} $changes->[0]->changes;

$schema->storage->debug(0);

is_deeply(\@events, [
  [ 'New child', 'was born' ],
  [ 'Former successor', 'died' ],
], 'multiple events on one date retain their people and descriptions');
is(scalar(@{ $counter->queries }), 1, 'dates, events, people and titles use one query');

# Exercise the widget through the real layout using an established historical
# birth, so this also catches accidental INSERT of unevaluated widget code.
{
  no warnings 'redefine';
  local *Succession::Model::get_feed_entries = sub { [] };

  my $test = Plack::Test->create(Succession->to_app);
  for my $day (qw(1982-06-18 1982-06-19 1982-06-21 1982-06-23 1982-06-24)) {
    my $res = $test->request(GET "/$day");
    ok($res->is_success, "$day renders");
    my $html = $res->decoded_content;
    if ($day eq '1982-06-18' || $day eq '1982-06-24') {
      unlike($html, qr{>Changes</h3>}, "$day hides changes outside the window");
    } else {
      like($html, qr{>Changes</h3>}, "$day shows the Changes widget");
      like($html, qr{William[^<]*</a> was born}, "$day shows the birth description");
    }
    like($html, qr{data-a2a-url="https://lineofsuccession\.co\.uk/$day"},
      'sharing targets the displayed date');
    is(scalar(() = $html =~ m{https://static\.addtoany\.com/menu/page\.js}g),
      1, 'sharing script appears once');
    unlike($html, qr/addthis/i, 'obsolete sharing integration is absent');
    unlike($html, qr/<%/, 'widget template directives are evaluated');
  }

  my $res = $test->request(GET '/dates');
  ok($res->is_success, 'static page renders with the extracted widgets');
  unlike($res->decoded_content, qr{>Changes</h3>}, 'static page has no Changes widget');
  like($res->decoded_content, qr{Enjoy Royal History.*Follow Line of Succession.*Adverts}s,
    'existing widgets retain their order');
}

done_testing();
