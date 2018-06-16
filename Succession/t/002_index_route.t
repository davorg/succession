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

my $now = DateTime->now->strftime('%d&nbsp;%B&nbsp;%Y');

like($res->decoded_content, qr/British Line of Succession on $now/,
     'Response looks sane');

done_testing();
