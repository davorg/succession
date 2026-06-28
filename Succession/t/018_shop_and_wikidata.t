use strict;
use warnings;

BEGIN {
  $ENV{SUCC_CACHE_DRIVER} = 'Null';
}

use HTTP::Request::Common;
use Plack::Test;
use Test::More;

use Succession;

my $test = Plack::Test->create(Succession->to_app);

my $shop = $test->request(GET '/shop');
ok($shop->is_success, 'shop page finds its data relative to appdir');
like($shop->header('ETag'), qr/^"[0-9a-f]{40}"$/, 'shop response has an ETag');
ok($shop->header('Last-Modified'), 'shop response has a Last-Modified header');

{
  # These methods were removed from Person; keep explicit traps here so a
  # future reintroduction cannot add server-side Wikidata calls unnoticed.
  no warnings qw[once redefine];

  local *Succession::Schema::Result::Person::image_url = sub {
    die 'person page called image_url during server render';
  };
  local *Succession::Schema::Result::Person::short_bio = sub {
    die 'person page called short_bio during server render';
  };

  my $person = $test->request(GET '/p/83d2fc-charles-iii');
  ok($person->is_success, 'person page renders without server-side Wikidata calls');
  like(
    $person->decoded_content,
    qr{https://www\.wikidata\.org/wiki/Special:EntityData/},
    'person page includes browser-side Wikidata enrichment',
  );
  like(
    $person->decoded_content,
    qr{const qid = 'Q\d+'},
    'person page supplies the Wikidata identifier to the browser',
  );
}

done_testing();
