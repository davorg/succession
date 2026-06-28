use strict;
use warnings;

BEGIN {
  $ENV{SUCC_CACHE_DRIVER} = 'Null';
}

use HTTP::Request::Common;
use Plack::Test;
use Test::More;

use Succession;

Succession->runner->apps->[0]->config->{amazon_tag} = q{test-<&'-21};

my $test = Plack::Test->create(Succession->to_app);
my $shop = $test->request(GET '/shop');

ok($shop->is_success, 'shop page renders');

my $shop_html = $shop->decoded_content;
like(
  $shop_html,
  qr{\?tag=test-%3C%26%27-21},
  'shop links use the configured Amazon tag',
);

my $amazon_store_tag = quotemeta q{tag: "test-\u003c\u0026'-21"};
is(
  () = $shop_html =~ /$amazon_store_tag/g,
  2,
  'Amazon Store JavaScript calls use the configured Amazon tag',
);

unlike(
  $shop_html,
  qr{davblog-21},
  'shop page does not render the default Amazon tag when configured',
);

done_testing();
