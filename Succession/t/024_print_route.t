use strict;
use warnings;

BEGIN { $ENV{SUCC_CACHE_DRIVER} = 'Null' }

use Test::More;
use HTTP::Request::Common;
use Plack::Test;
use DateTime;
use Succession;
use Succession::Print;

my $last_svg;
my $preview_png = Succession::Print->can('preview_png');
{
  no warnings 'redefine';
  *Succession::Print::preview_png = sub {
    my ($class, $svg) = @_;
    $last_svg = $svg;
    return $preview_png->($class, $svg);
  };
}

my $test = Plack::Test->create(Succession->to_app);
my $url = '/print.png?date=1962-09-07&sovereign_id=4';
my $response = $test->request(GET $url);
is($response->code, 200, 'valid date and monarch return a print');
like($response->header('Content-Type'), qr{^image/png}, 'PNG content type');
like($response->header('Content-Disposition'), qr{succession-1962-09-07-specimen\.png}, 'dated filename');
is(substr($response->content, 0, 8), "\x89PNG\r\n\x1a\n", 'actual PNG bytes returned');
is(unpack('N', substr($response->content, 16, 4)), 1000, 'preview width capped at 1000 pixels');
my $svg = $last_svg;
like($svg, qr{<svg .*width="297mm" height="420mm"}, 'A3 portrait SVG');
like($svg, qr{7 September 1962}, 'requested date appears');
like($svg, qr{Queen Elizabeth II}, 'real historical data appears');
like($svg, qr{Sovereign on this date}, 'sovereign annotation appears');
like($svg, qr{Abdicated}, 'exclusion appears');
unlike($svg, qr{<!DOCTYPE html|<html}, 'no HTML layout');
is($test->request(GET "$url&size=A3")->content, $response->content, 'explicit default size produces identical output');
is($test->request(GET "$url&order=succession")->content, $response->content, 'prints default to succession order');
like($svg, qr{The Prince Charles.*The Prince Andrew.*The Princess Anne}s, 'succession order places Andrew before Anne');
like($svg, qr{Prince Edward, Duke of Kent.*Prince Michael of Kent.*Princess Alexandra of Kent}s, 'Kent siblings follow succession order');
my $birth_response = $test->request(GET "$url&order=birth");
is($birth_response->code, 200, 'birth order is supported');
like($last_svg, qr{The Prince Charles.*The Princess Anne.*The Prince Andrew}s, 'birth order places Anne before Andrew');

for my $query (
  '', 'date=1962-09-07', 'date=1962-02-30&sovereign_id=4',
  'date=1962/09/07&sovereign_id=4', 'date=1819-12-31&sovereign_id=4',
  'date=9999-01-01&sovereign_id=4', 'date=1962-09-07&sovereign_id=abc',
  'date=1962-09-07&sovereign_id=999999', 'date=1962-09-07&sovereign_id=10',
  'date=1962-09-07&sovereign_id=4&size=A2',
  'date=1962-09-07&sovereign_id=4&order=unknown',
) {
  my $bad = $test->request(GET "/print.png?$query");
  is($bad->code, 400, "invalid parameters rejected: $query");
  like($bad->header('Content-Type'), qr{^text/plain}, 'error is plain text');
}

my $data = { name => 'A < B & C', alive_on_date => 1, age => '2 months', children => [] };
my $modern = $test->request(GET '/print.png?date=2025-09-07&sovereign_id=1&order=birth');
is($modern->code, 200, 'reported modern print URL succeeds');
like($last_svg, qr{Arthur Chatto</*.*?>31</text>}s,
  'Arthur Chatto receives succession number 31 in SVG');
my %args = (data => $data, date => DateTime->new(year => 1962, month => 9, day => 7));
my $escaped = Succession::Print->render(%args);
like($escaped, qr{A &lt; B &amp; C}, 'data is XML escaped');
like($escaped, qr{2 months}, 'infant age is preserved');
$data->{children} = [map { { name => "Child $_", children => [] } } 1 .. 40];
ok(!defined Succession::Print->render(%args), 'oversized hierarchy refused');

{
  no warnings 'redefine';
  local *Succession::Model::succession_tree = sub { $data };
  is($test->request(GET $url)->code, 422, 'oversized hierarchy returns 422');
}

my $legacy = $test->request(GET '/print.svg?date=1962-09-07&sovereign_id=4&order=birth');
is($legacy->code, 302, 'old SVG route redirects');
like($legacy->header('Location'), qr{/print\.png\?date=1962-09-07&sovereign_id=4&order=birth$}, 'redirect preserves design parameters');
unlike($legacy->content, qr{<svg}, 'legacy route does not expose vectors');
unlike($escaped, qr{SPECIMEN}, 'internal production SVG remains clean');
isnt($preview_png->('Succession::Print', $escaped), do {
  my $dir = File::Temp->newdir;
  my $input = Path::Tiny::path("$dir", 'clean.svg');
  my $output = Path::Tiny::path("$dir", 'clean.png');
  $input->spew_utf8($escaped);
  system('rsvg-convert', '--width', '1000', '--output', "$output", "$input") == 0 or die 'conversion failed';
  $output->slurp_raw;
}, 'public preview differs from clean raster through watermark');

done_testing;
