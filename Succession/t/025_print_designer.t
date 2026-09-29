use strict;
use warnings;
BEGIN { $ENV{SUCC_CACHE_DRIVER} = 'Null' }
use Test::More;
use DateTime;
use HTTP::Request::Common;
use Plack::Test;
use Succession;

my $model = Succession::Model->new(cache => CHI->new(driver => 'Memory', datastore => {}));
sub date { DateTime->new(year => substr($_[0],0,4), month => substr($_[0],5,2), day => substr($_[0],8,2)) }
sub flatten { my ($n) = @_; return ($n, map { flatten($_) } @{$n->{children}}) }
for my $day (qw(1820-01-29 1837-06-19 1837-06-20 1936-12-11 1936-12-12 1962-09-07 2022-09-07 2022-09-08 2025-01-21 2025-01-22 2025-09-07)) {
  my $d = date($day);
  my $tree = $model->succession_print_data($d);
  my @rows = flatten($tree);
  cmp_ok(scalar @rows, '<=', 30, "$day caps all displayed people at 30");
  ok(@rows > 0, "$day has a family");
  my $current = $model->sovereign_on_date($d);
  my ($expected, $largest) = (undef, 0);
  for my $s ($model->sovereign_rs->search({start => {'<=' => $current->start->ymd}}, {order_by => {-desc => 'start'}})->all) {
    next unless $s->id == $current->id || (defined $s->person->died && $s->person->died <= $d);
    my $candidate = $model->succession_tree($s->id, $d, 'succession');
    my @candidate_rows = flatten($candidate);
    if (@candidate_rows > $largest) { $expected = $candidate; $largest = scalar @candidate_rows }
    last if @candidate_rows >= 25;
  }
  my @expected = flatten($expected);
  splice @expected, 30 if @expected > 30;
  is_deeply([map {$_->{name}} @rows], [map {$_->{name}} @expected], "$day selects first qualifying monarch or largest fallback, retaining display prefix");
  ok(!(grep { $_->{born} gt $day } @rows), "$day includes no future births");
}
my $before = $model->succession_print_data(date('2025-01-21'));
my $after = $model->succession_print_data(date('2025-01-22'));
ok(!(grep { $_->{born} eq '2025-01-22' } flatten($before)), 'Athena absent before birth');
ok((grep { $_->{born} eq '2025-01-22' } flatten($after)), 'Athena present on birth date');
for my $pair (['2022-09-07', '1926-04-21'], ['2022-09-08', '1948-11-14']) {
  my @sovereigns = grep { $_->{current_sovereign} } flatten($model->succession_print_data(date($pair->[0])));
  is_deeply([map {$_->{born}} @sovereigns], [$pair->[1]], 'correct sovereign on ' . $pair->[0]);
}
my ($william_before) = grep { $_->{born} eq '1765-08-21' }
  flatten($model->succession_print_data(date('1837-06-19')));
my @accession_rows = flatten($model->succession_print_data(date('1837-06-20')));
my ($william_after) = grep { $_->{born} eq '1765-08-21' } @accession_rows;
ok($william_before->{alive_on_date}, 'William IV alive the day before his death');
ok(!$william_after->{alive_on_date}, 'William IV deceased by end of his death date');
ok(!defined $william_after->{succession_number}, 'deceased William IV has no rank');
is_deeply([map { $_->{born} } grep { $_->{current_sovereign} } @accession_rows],
  ['1819-05-24'], 'Victoria is sovereign at the end of accession day');
my $d = date('1962-09-07');
my $birth = $model->succession_print_data($d, 'birth');
my $succ = $model->succession_print_data($d, 'succession');
is($birth->{name}, $succ->{name}, 'ordering does not change root selection');
isnt(join('|', map {$_->{name}} flatten($birth)), join('|', map {$_->{name}} flatten($succ)), 'ordering changes displayed siblings');
# Prefix selection must preserve parents and must not mutate a reusable tree.
my $source = {name => 'root', children => [{name => 'parent', children => [map {{name => "child $_", children => []}} 1..35]}]};
my $remaining = 30;
my $trimmed = $model->_print_tree_prefix($source, \$remaining);
my @trimmed_rows = flatten($trimmed);
is(scalar @trimmed_rows, 30, 'prefix includes exactly 30 people');
is($trimmed->{children}[0]{name}, 'parent', 'connecting parent survives');
is(scalar @{$source->{children}[0]{children}}, 35, 'source tree unchanged');

my $test = Plack::Test->create(Succession->to_app);
my $page = $test->request(GET '/print');
is($page->code, 200, 'designer page loads');
like($page->decoded_content, qr{id="print-image" alt="" hidden}, 'initial preview is blank');
unlike($page->decoded_content, qr{href="/print">Design your print}, 'designer is not linked from navigation');
like($page->decoded_content, qr{min="1820-01-29"}, 'date control uses supported lower bound');
my $auto = $test->request(GET '/print.png?date=1962-09-07&order=birth');
is($auto->code, 200, 'automatic-root preview succeeds');
is(substr($auto->content, 0, 8), "\x89PNG\r\n\x1a\n", 'automatic preview returns actual PNG');
{
  no warnings 'redefine';
  local *Succession::Model::succession_print_data = sub { die 'private database details' };
  my $failure = $test->request(GET '/print.png?date=1962-09-07');
  is($failure->code, 500, 'generation failure returns 500');
  unlike($failure->content, qr/private database/, 'internal error is not disclosed');
  like($failure->content, qr/try again later/, 'generation failure has helpful message');
}
done_testing;
