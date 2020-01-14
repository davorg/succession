use strict;
use warnings;

use Succession;
use Test::More;
use Plack::Test;
use HTTP::Request::Common;
use DateTime;

my $app = Succession->to_app;
is( ref $app, 'CODE', 'Got app' );

my $test = Plack::Test->create($app);
my $res  = $test->request( GET '/' );

ok( $res->is_success, '[GET /] successful' );

my $html_display_fmt = '%e&nbsp;%B&nbsp;%Y';

my $now = DateTime->now->strftime($html_display_fmt);

like($res->decoded_content, qr/British Line of Succession on $now/,
     'Response looks sane');

my $date = DateTime->new(year => 1952, month => 2, day => 6);
my $iso_date = $date->ymd;
my $str_date = $date->strftime($html_display_fmt);

$res = $test->request( GET "/$iso_date" );

ok( $res->is_success, "[GET /$iso_date] successful" );

like($res->decoded_content, qr/British Line of Succession on $str_date/,
     'Response looks sane');

# static pages
for (qw[dates changes]) {
  $res = $test->request( GET "/$_" );
  ok( $res->is_success, "[GET /$_] successful");
}

done_testing();
