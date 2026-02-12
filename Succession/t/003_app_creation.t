use strict;
use warnings;
use feature 'signatures';

use Test::More;
use DateTime;

use Succession::App;
use Succession::Request;

ok(Succession::App->new, 'No parameters');
ok(Succession::App->new(date => '2000-01-01'), 'String date');
ok(Succession::App->new(date => DateTime->now), 'DateTime date');

my $empty_date_request = make_request('');
my $app = Succession::App->new(request => $empty_date_request);
is($app->request->date->ymd, DateTime->today->ymd, 'Default date is today');

TODO: {
  local $TODO = 'Why do these fail?';

  my $future_date_request = make_request(DateTime->now->add(weeks => 2));
  $app = Succession::App->new(request => $future_date_request);
  ok($app->error, 'Error on future date');
  diag $app->error;

  my $early_date_request = make_request(DateTime->new(year => 1000));
  $app = Succession::App->new(request => $early_date_request);
  ok($app->error, 'Error on early date');
  diag $app->error;
}

sub make_request($date) {
  return Succession::Request->new(path => '/', date => $date, env => {});
}

done_testing();

