use strict;
use warnings;

BEGIN { $ENV{SUCC_CACHE_DRIVER} = 'Null' }

use Digest::SHA qw(sha256_hex);
use HTTP::Request::Common;
use Plack::Test;
use Test::More;

use Succession;
use Succession::Schema;

{
  package Local::PrintGalleryQueryCounter;
  use parent 'DBIx::Class::Storage::Statistics';
  sub query_start { push @{ $_[0]->{queries} }, $_[1] }
  sub query_end { }
  sub queries { $_[0]->{queries} // [] }
}

{
  no warnings 'redefine';
  local *Succession::Model::get_feed_entries = sub { [] };
  my $schema = Succession::Schema->get_schema;
  my $counter = Local::PrintGalleryQueryCounter->new;
  $schema->storage->debugobj($counter);
  $schema->storage->debug(1);
  my $test = Plack::Test->create(Succession->to_app);
  my $page = $test->request(GET '/shop/prints');
  $schema->storage->debug(0);

  ok($page->is_success, 'print gallery page renders');
  my $html = $page->decoded_content;
  like($html, qr{<title>Personalised British Line of Succession Prints</title>},
    'nested print page has its own title rather than the parent shop title');
  like($html, qr{<meta name="description" content="Coming soon: personalised British line of succession prints},
    'nested print page has its own description');
  like($html, qr{<link rel="canonical" href="https://lineofsuccession\.co\.uk/shop/prints"},
    'print gallery has its own canonical URL');
  like($html, qr{Coming soon}, 'availability is clearly coming soon');
  like($html, qr{any date that is special\s+to you}, 'copy explains the personalised date');
  like($html, qr{href="/print">Try your special date</a>}, 'gallery links to the existing sample designer');
  like($html, qr{class="navbar-brand" href="/"}, 'normal site navigation is available');
  like($html, qr{href="/r/how-many-people-are-in-the-line-of-succession"}, 'reference menu is present');
  like($html, qr{<footer class="footer">}, 'normal site footer is present');
  unlike($html, qr{class="subscribe-box print-shop-widget"}, 'print gallery hides its own sidebar advert');
  like($html, qr{class="modal fade prints-lightbox"}, 'gallery includes a modal');
  is(scalar(() = $html =~ /class="carousel-item(?: active)?"/g), 3, 'carousel has all three images');
  is(scalar(() = $html =~ /data-print-slide="[012]"/g), 3, 'each thumbnail selects its carousel slide');
  unlike($html, qr{application/ld\+json}, 'static gallery omits succession JSON-LD');
  is(scalar(grep { /^SELECT\b/i } @{ $counter->queries }), 0, 'gallery does not query the database');

  my @images = $html =~ m{<a class="prints-gallery-link" href="([^"]+)"}g;
  is(scalar(@images), 3, 'gallery has exactly three linked thumbnails');
  for my $url (@images) {
    like($url, qr{^/images/prints/[^ ]+\.png$}, 'image URL safely encodes spaces in the original filename');
    my $image = $test->request(GET $url);
    ok($image->is_success, 'linked gallery image is served');
    like($image->header('Content-Type'), qr{^image/png}, 'gallery image has PNG content type');
    is(substr($image->content, 0, 8), "\x89PNG\r\n\x1a\n", 'gallery image contains PNG bytes');
  }

  my ($script_url, $digest) = $html =~ m{src="(/js/print-gallery\.js\?v=([a-f0-9]{16}))"};
  ok($script_url, 'gallery script uses a content-fingerprinted URL');
  my $script = $test->request(GET($script_url // '/js/print-gallery.js'));
  ok($script->is_success, 'gallery script is served');
  is($digest, substr(sha256_hex($script->content), 0, 16), 'script fingerprint matches the served JavaScript');

  for my $path ('/', '/shop', '/print', '/mcp') {
    my $other = $test->request(GET $path);
    ok($other->is_success, "$path still renders");
    is(scalar(() = $other->decoded_content =~ /class="subscribe-box print-shop-widget"/g),
      1, "$path displays the print-shop widget once");
    like($other->decoded_content, qr{href="/shop/prints">Preview the prints</a>}, "$path widget links to the gallery");
    unlike($other->decoded_content, qr{/js/print-gallery\.js}, "$path does not load gallery JavaScript");
  }
  my $query_page = $test->request(GET '/shop/prints?source=sidebar');
  ok($query_page->is_success, 'gallery with a query string renders');
  unlike($query_page->decoded_content, qr{class="subscribe-box print-shop-widget"},
    'gallery with a query string also hides its own advert');
}

done_testing();
