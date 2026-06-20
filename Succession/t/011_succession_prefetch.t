use strict;
use warnings;

BEGIN {
  $ENV{SUCC_CACHE_DRIVER} = 'Null';
}

use CHI;
use DateTime;
use Test::More;

use Succession::Model;

my $model = Succession::Model->new(
  cache => CHI->new(driver => 'Null'),
);

for my $date (
  DateTime->new(year => 1952, month => 2, day => 6),
  DateTime->today,
) {
  my $period = $model->schema->succession_periods->succession_on_date($date);
  ok($period, 'found the succession period for ' . $date->ymd);

  my @expected_ids = $period->succession_entries->search(undef, {
    order_by => 'rank',
  })->get_column('person_id')->all;

  my $people = $model->succession_on_date($date);

  is_deeply(
    [ map { $_->id } @$people ],
    \@expected_ids,
    'prefetched people remain in rank order for ' . $date->ymd,
  );
}

done_testing();
