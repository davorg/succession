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

my $schema = Succession::Schema->connect('dbi:SQLite:dbname=:memory:', '', '');
$schema->deploy;
my %rows = map {
  $_ => $schema->resultset('ChangeDate')->create({ change_date => $_ })
} qw(2025-01-22 2026-08-03 2026-09-01);

{
  no warnings 'once';
  local $DBIx::Class::ResultSourceHandle::thaw_schema = $schema;

  my $cache = CHI->new(driver => 'Memory', datastore => {});
  # Cached results from the timestamp comparisons must not survive the fix.
  $cache->set('prev_change|0|2026-08-03', $rows{'2026-08-03'});
  $cache->set('next_change|1|2026-08-03', $rows{'2026-09-01'});
  my $model = Succession::Model->new(schema => $schema, cache => $cache);

  for my $case (
    [ '2026-08-03', 0, '2025-01-22', '2026-09-01' ],
    [ '2026-08-03', 1, '2026-08-03', '2026-08-03' ],
    [ '2026-08-04', 0, '2026-08-03', '2026-09-01' ],
    [ '2026-08-04', 1, '2026-08-03', '2026-09-01' ],
    [ '2025-01-22', 0, undef, '2026-08-03' ],
    [ '2026-09-01', 0, '2026-08-03', undef ],
  ) {
    my ($day, $include_current, $expected_prev, $expected_next) = @$case;
    my ($year, $month, $date) = split /-/, $day;
    my $dt = DateTime->new(year => $year, month => $month, day => $date);
    my $prev = $model->get_prev_change_date($dt, $include_current);
    my $next = $model->get_next_change_date($dt, $include_current);
    is($prev ? $prev->change_date->ymd : undef, $expected_prev,
      "$day previous change with include_current=$include_current");
    is($next ? $next->change_date->ymd : undef, $expected_next,
      "$day next change with include_current=$include_current");
  }

  my $midday = DateTime->new(year => 2026, month => 8, day => 3, hour => 12);
  is($model->get_prev_change_date($midday)->change_date->ymd, '2025-01-22',
    'previous change excludes the selected day even when its time is midday');
  is($model->get_canonical_date($midday), '2026-08-03',
    'canonical lookup can still include the selected change date');
}

{
  no warnings 'redefine';
  local *Succession::Model::get_feed_entries = sub { [] };
  my $test = Plack::Test->create(Succession->to_app);
  my $res = $test->request(GET '/2026-08-03');
  ok($res->is_success, 'the reported change page renders');
  like($res->decoded_content, qr{Previous change:\s*<a[^>]*href="/2025-01-22"},
    'the previous change link points to the earlier change page');
  unlike($res->decoded_content, qr{Previous change:\s*<a[^>]*href="/2026-08-03"},
    'the previous change link never points to the current page');
}

done_testing();
