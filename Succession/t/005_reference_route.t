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
my $res = $test->request( GET '/r/how-many-people-are-in-the-line-of-succession' );
ok( $res->is_success, '[GET /r/about] successful' );
like( $res->decoded_content, qr/How Many People/, 'Reference page content rendered' );
like( $res->decoded_content, qr/<h2>/, 'Markdown converted to HTML' );

# Test that frontmatter is stripped from rendered output
unlike( $res->decoded_content, qr/---/, 'Frontmatter delimiters not in rendered content' );

# Test that the title from frontmatter is used in the <title> tag
like( $res->decoded_content, qr{<title>How Many People}, 'Frontmatter title used in <title> tag' );

# Test that the reference menu is present in the navbar and links to the about page
like( $res->decoded_content, qr{href="/r/how-many-people}, 'Reference navbar menu contains link to a ref page' );

# Test a non-existent reference page returns 404
$res = $test->request( GET '/r/no-such-page' );
is( $res->code, 404, '[GET /r/no-such-page] returns 404' );

done_testing();
