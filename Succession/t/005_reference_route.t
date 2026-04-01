use strict;
use warnings;

use Succession;
use Test::More;
use Plack::Test;
use HTTP::Request::Common;

my $app = Succession->to_app;
is( ref $app, 'CODE', 'Got app' );

my $test = Plack::Test->create($app);

# Test a valid reference page
my $res = $test->request( GET '/r/about' );
ok( $res->is_success, '[GET /r/about] successful' );
like( $res->decoded_content, qr/About This Site/, 'Reference page content rendered' );
like( $res->decoded_content, qr/<h1>/, 'Markdown converted to HTML' );

# Test a non-existent reference page returns 404
$res = $test->request( GET '/r/no-such-page' );
is( $res->code, 404, '[GET /r/no-such-page] returns 404' );

done_testing();
