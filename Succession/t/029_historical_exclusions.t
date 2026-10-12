use strict;
use warnings;
BEGIN { $ENV{SUCC_CACHE_DRIVER} = 'Null' }

use CHI;
use DateTime;
use HTTP::Request::Common;
use JSON::MaybeXS qw(decode_json);
use Plack::Test;
use Test::More;
use Succession;
use Succession::Model;
use Succession::Snapshot;

my $date = DateTime->new(year => 1990, month => 1, day => 1);
my $model = Succession::Model->new(cache => CHI->new(driver => 'Null'));
my $rows = $model->succession_display_on_date($date);
is(scalar(@$rows), 34, '1990 includes four exclusions before the thirtieth eligible successor');
is_deeply([ map { $_->{rank} } grep { defined $_->{rank} } @$rows ], [ 1 .. 30 ],
  '1990 has thirty contiguous eligible ranks');
is_deeply([ map { $_->{person}->id } grep { !defined $_->{rank} } @$rows ],
  [ 43, 42, 430, 431 ], '1990 includes the exclusion beyond the old truncated list');
my @eligible_ids = map { $_->id } @{ $model->succession_on_date($date) };
is_deeply([ @eligible_ids[27 .. 29] ],
  [ 432, 433, 35 ], '1990 recovers the three missing eligible successors');

my $generator = Succession::Snapshot->new(schema => $model->schema);
my @mismatches;
for my $period ($model->schema->resultset('SuccessionPeriod')->all) {
  for my $day ($period->from_date,
    ($period->to_date ? $period->to_date->clone->subtract(days => 1) : DateTime->today)) {
    my $expected = $generator->line_on_date($day);
    my $actual = $model->succession_display_on_date($day);
    my $a = join ':', map { $_->{person}->id . ':' . ($_->{rank} // 'X') } @$actual;
    my $e = join ':', map { $_->{person_id} . ':' . ($_->{succession_rank} // 'X') } @$expected;
    push @mismatches, $day->ymd if $a ne $e;
  }
}
is_deeply(\@mismatches, [], 'every period agrees with the genealogy at both date boundaries');

{
  no warnings 'redefine';
  local *Succession::Model::get_feed_entries = sub { [] };
  my $res = Plack::Test->create(Succession->to_app)->request(GET '/1990-01-01');
  ok($res->is_success, 'reported historical page renders');
  my $html = $res->decoded_content;
  unlike($html, qr{We don't have thirty}, 'reported historical page no longer warns about insufficient data');
  my ($list) = $html =~ m{<ul class="succession-list">(.*?)</ul>}s;
  is(scalar(() = $list =~ /<li\b/g), 34, 'historical page displays all thirty-four people');
  like($list, qr{Excluded: Married a Catholic}, 'historical reasons are displayed');
  like($list, qr{Excluded: Illegitimate}, 'illegitimacy reasons are displayed');
  my ($json) = $html =~ m{<script type="application/ld\+json">(.*?)</script>}s;
  is(scalar(@{ decode_json($json)->{itemListElement} }), 31,
    'historical JSON-LD includes only the sovereign and eligible successors');
}

done_testing();
