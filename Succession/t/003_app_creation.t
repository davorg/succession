use strict;
use warnings;

use Test::More;
use Test::Exception;
use DateTime;

use Succession::App;

ok(Succession::App->new, 'No parameters');
ok(Succession::App->new(date => '2000-01-01'), 'String date');
ok(Succession::App->new(date => DateTime->now), 'DateTime date');
throws_ok { Succession::App->new(date => '') } qr/Validation failed/,
  'Empty string date throws error';
throws_ok { Succession::App->new(date => DateTime->now->add(weeks => 2)) }
  qr/Date cannot be after today/,
  'Date in the future throws error';
throws_ok { Succession::App->new(date => '2000-09-31') }
  qr/Validation failed/,
  'Invalid date throws error';
throws_ok { Succession::App->new(date => '1000-01-01') }
  qr/Date cannot be before/,
  'Too early date throws error';

done_testing();

