use strict;
use warnings;

use CHI;
use Test::More;

use Succession::Model;

my $xml = <<'XML';
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>Succession test feed</title>
    <link>https://blog.example.test/</link>
    <description>Test posts</description>
    <item>
      <title>First post</title>
      <link>https://blog.example.test/first</link>
      <description>First post body</description>
    </item>
  </channel>
</rss>
XML

my $fetch_count = 0;
my $fail_fetch  = 0;
my $cache = CHI->new(
  driver    => 'Memory',
  global    => 0,
  namespace => "feed-test-$$",
);

my $model = Succession::Model->new(
  cache => $cache,
  feed_fetcher => sub {
    ++$fetch_count;
    die "feed unavailable\n" if $fail_fetch;
    return $xml;
  },
);

my $expected = [{
  title => 'First post',
  link  => 'https://blog.example.test/first',
}];

is_deeply($model->get_feed_entries, $expected, 'parsed feed into plain entry data');
is_deeply($model->get_feed_entries, $expected, 'reused the fresh cached feed');
is($fetch_count, 1, 'fresh feed was fetched once');

$cache->remove('blog_feed_entries_v1');
$fail_fetch = 1;

my $warning = '';
{
  local $SIG{__WARN__} = sub { $warning .= join '', @_ };
  is_deeply($model->get_feed_entries, $expected, 'served stale data after refresh failure');
}
like($warning, qr/Blog feed refresh failed: feed unavailable/, 'logged the refresh failure');
is($fetch_count, 2, 'attempted one refresh before using stale data');

is_deeply($model->get_feed_entries, $expected, 'failure fallback has a short backoff cache');
is($fetch_count, 2, 'did not retry during the failure backoff');

my $empty_cache = CHI->new(
  driver    => 'Memory',
  global    => 0,
  namespace => "empty-feed-test-$$",
);
my $failing_model = Succession::Model->new(
  cache => $empty_cache,
  feed_fetcher => sub { die "still unavailable\n" },
);

{
  local $SIG{__WARN__} = sub { };
  is_deeply($failing_model->get_feed_entries, [], 'omitted the menu when no feed data exists');
}

done_testing();
