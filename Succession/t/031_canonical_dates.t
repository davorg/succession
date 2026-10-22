use strict;
use warnings;

BEGIN { $ENV{SUCC_CACHE_DRIVER} = 'Null' }

use CHI;
use DateTime;
use HTTP::Request::Common;
use Plack::Test;
use Test::More;

use Succession;
use Succession::App;
use Succession::Model;
use Succession::Request;
use Succession::Schema;

{
  package Local::CanonicalQueryCounter;
  use parent 'DBIx::Class::Storage::Statistics';
  sub query_start { push @{ $_[0]->{queries} }, $_[1] }
  sub query_end { }
  sub queries { $_[0]->{queries} // [] }
}

sub date {
  my ($day, $hour) = @_;
  my ($year, $month, $date) = split /-/, $day;
  return DateTime->new(year => $year, month => $month, day => $date, hour => $hour // 0);
}

my $schema = Succession::Schema->connect('dbi:SQLite:dbname=:memory:', '', '', { quote_names => 1 });
$schema->deploy;
$schema->resultset('ChangeDate')->populate([
  map { +{ change_date => $_ } } qw(2000-01-01 2000-02-01 2000-03-01)
]);
my $model = Succession::Model->new(schema => $schema, cache => CHI->new(driver => 'Null'));

for my $case (
  [ '1999-12-31', '', 'before the first change falls back to the homepage' ],
  [ '2000-01-01', '2000-01-01', 'the first change includes itself' ],
  [ '2000-01-15', '2000-01-01', 'between changes uses the preceding change' ],
  [ '2000-02-01', '2000-02-01', 'a historical change includes itself' ],
  [ '2000-02-29', '2000-02-01', 'the day before the latest change is historical' ],
  [ '2000-03-01', '', 'the latest change uses the homepage' ],
  [ '2000-03-02', '', 'after the latest change uses the homepage' ],
) {
  my ($day, $expected, $description) = @$case;
  for my $hour (0, 12) {
    is($model->get_canonical_date(date($day, $hour)), $expected, "$description at hour $hour");
  }
  my $request = Succession::Request->new(env => { PATH_INFO => "/$day", REQUEST_METHOD => 'GET' });
  my $app = Succession::App->new(request => $request, model => $model);
  is($app->canonical, "/$expected", "$day builds the expected canonical path");
}

my $request = Succession::Request->new(env => { PATH_INFO => '/', REQUEST_METHOD => 'GET' });
is(Succession::App->new(request => $request, model => $model)->canonical, '/',
  'the homepage keeps its own canonical path');

$schema->resultset('ChangeDate')->delete;
is($model->get_canonical_date(date('2000-01-01')), '', 'an empty change history uses the homepage');
$schema->resultset('ChangeDate')->create({ change_date => '2000-01-01' });
for my $day (qw(1999-12-31 2000-01-01 2000-01-02)) {
  is($model->get_canonical_date(date($day)), '', "$day uses the homepage with a single change");
}

{
  no warnings 'once';
  local $DBIx::Class::ResultSourceHandle::thaw_schema = $schema;
  $schema->resultset('ChangeDate')->create({ change_date => '2000-02-01' });
  my $cached = Succession::Model->new(schema => $schema,
    cache => CHI->new(driver => 'Memory', datastore => {}));
  is($cached->get_canonical_date(date('2000-01-15')), '2000-01-01', 'a cached lookup finds the historical change');
  is($cached->get_canonical_date(date('2000-01-15', 12)), '2000-01-01', 'cached dates ignore the time of day');
  is($cached->get_canonical_date(date('2000-02-01')), '', 'a cached lookup stores the homepage result');
  is($cached->get_canonical_date(date('2000-02-01', 12)), '', 'the cached homepage result is reused at midday');
}

{
  no warnings 'redefine';
  local *Succession::Model::get_feed_entries = sub { [] };
  my $web_schema = Succession::Schema->get_schema;
  my $latest_change = $web_schema->resultset('ChangeDate')->get_column('change_date')->max;
  my $test = Plack::Test->create(Succession->to_app);
  for my $case (
    [ '1952-02-06', '/1952-02-06', 8, 1 ],
    [ $latest_change, '/', 7, 0 ],
  ) {
    my ($day, $canonical, $budget, $expected_preceding_lookups) = @$case;
    my $counter = Local::CanonicalQueryCounter->new;
    $web_schema->storage->debugobj($counter);
    $web_schema->storage->debug(1);
    my $res = $test->request(GET "/$day");
    $web_schema->storage->debug(0);
    ok($res->is_success, "$day renders with a cold cache");
    my $expected_url = 'https://lineofsuccession.co.uk' . $canonical;
    like($res->decoded_content, qr{<link rel="canonical" href="\Q$expected_url\E"},
      "$day advertises the expected canonical URL without a redirect");
    my @selects = grep { /^SELECT\b/i } @{ $counter->queries };
    cmp_ok(scalar(@selects), '<=', $budget, "$day stays within its SELECT budget");
    is(scalar(grep { /FROM "change_date" "me".*WHERE.*"change_date" <=/s } @selects),
      $expected_preceding_lookups, "$day only looks up a preceding canonical change when needed");
    is(scalar(grep { /SELECT MAX\(.*"change_date"/s } @selects), 1,
      "$day checks the latest change date once");
  }
}

done_testing();
