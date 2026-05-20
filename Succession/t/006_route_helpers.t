use strict;
use warnings;

use Test::More;

use Succession::Request;
use Succession::RouteHelpers;

my $helpers = Succession::RouteHelpers->new;

my ($title, $body) = $helpers->parse_frontmatter(<<'MARKDOWN');
---
title: A Page Title
---

# Heading
MARKDOWN

is($title, 'A Page Title', 'Title parsed from frontmatter');
is($body, "\n# Heading\n", 'Frontmatter stripped from body');

($title, $body) = $helpers->parse_frontmatter("# No frontmatter\n");
ok(!defined $title, 'No title when frontmatter missing');
is($body, "# No frontmatter\n", 'Body unchanged without frontmatter');

my $request = Succession::Request->new(
  path => '/',
  env  => {
    HTTP_IF_NONE_MATCH => 'match-etag',
  },
);
ok($helpers->is_not_modified($request, 'match-etag', 'Wed, 01 Jan 2025 00:00:00 GMT'),
  'If-None-Match header triggers not-modified check');

$request = Succession::Request->new(
  path => '/',
  env  => {
    HTTP_IF_MODIFIED_SINCE => 'Wed, 01 Jan 2025 00:00:00 GMT',
  },
);
ok($helpers->is_not_modified($request, 'etag', 'Wed, 01 Jan 2025 00:00:00 GMT'),
  'If-Modified-Since header triggers not-modified check');

$request = Succession::Request->new(path => '/', env => {});
ok(!$helpers->is_not_modified($request, 'etag', 'Wed, 01 Jan 2025 00:00:00 GMT'),
  'No conditional headers means modified');

my $app = $helpers->make_app({
  request   => Succession::Request->new(path => '/', env => {}),
  date      => '2000-01-01',
  list_size => 12,
});
isa_ok($app, 'Succession::App');
is($app->list_size, 12, 'App list_size passed through helper');

done_testing();
