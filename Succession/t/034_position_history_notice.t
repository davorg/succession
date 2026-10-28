use strict;
use warnings;

BEGIN { $ENV{SUCC_CACHE_DRIVER} = 'Null' }

use DateTime;
use FindBin;
use HTTP::Request::Common;
use Plack::Test;
use Template;
use Test::More;

use Succession;
use Succession::App;

sub date {
  my ($ymd) = @_;
  my ($year, $month, $day) = split /-/, $ymd;
  return DateTime->new(year => $year, month => $month, day => $day);
}

my $tt = Template->new({
  INCLUDE_PATH => "$FindBin::Bin/../views",
  START_TAG => '<%', END_TAG => '%>',
});

sub render_person {
  my ($born, $earliest, $has_positions) = @_;
  my $positions = $has_positions
    ? [{ position => 1, start => date($earliest) }] : [];
  my $html = '';
  $tt->process('person.tt', {
    app => Succession::App->new(earliest => date($earliest)),
    person => { name => 'Test person', born => $born ? date($born) : undef },
    positions => $positions, collapsed_positions => $positions,
    titles => [], children => [], siblings => [], exclusions => [],
  }, \$html) or die $tt->error;
  return $html;
}

my $html = render_person('1819-05-24', '1820-01-29', 1);
like($html, qr{<p class="small text-muted mb-0" id="position-history-notice">},
  'notice uses small, muted text');
like($html, qr{begin on 29 January 1820}, 'notice formats the App cutoff');
like($html, qr{Positions held before\s+that date are not yet included},
  'notice explains the missing history');
like($html, qr{<ul id="positions-list">.*?</ul>\s*<p[^>]+id="position-history-notice">.*?</p>\s*</div>\s*<div class="card-soft">\s*<h2>Relations</h2>}s,
  'notice sits at the bottom of the Positions card');

for my $case (
  ['1820-01-29', 1, 'born exactly on the cutoff'],
  ['1820-01-30', 1, 'born after the cutoff'],
  ['1819-05-24', 0, 'born before the cutoff but without position history'],
) {
  unlike(render_person($case->[0], '1820-01-29', $case->[1]),
    qr{position-history-notice}, "no notice for a person $case->[2]");
}

like(render_person('1819-05-24', '1830-06-26', 1),
  qr{begin on 26 June 1830}, 'notice follows a different App cutoff');
unlike(render_person('1819-05-24', '1810-01-01', 1),
  qr{position-history-notice}, 'adding earlier coverage removes an unnecessary notice');

{
  no warnings 'redefine';
  local *Succession::Model::get_feed_entries = sub { [] };
  my $test = Plack::Test->create(Succession->to_app);
  my $victoria = $test->request(GET '/p/82e1ca-queen-victoria');
  ok($victoria->is_success, 'Victoria page renders');
  my $cutoff = Succession::App->new->earliest->strftime('%e %B %Y');
  $cutoff =~ s/^\s+//;
  like($victoria->decoded_content, qr{position-history-notice.*?begin on \Q$cutoff\E}s,
    'Victoria page displays the notice with the current App cutoff');

  my $charles = $test->request(GET '/p/83d2fc-charles-iii');
  ok($charles->is_success, 'Charles III page renders');
  unlike($charles->decoded_content, qr{position-history-notice},
    'Charles III page does not show the notice');
}

done_testing();
