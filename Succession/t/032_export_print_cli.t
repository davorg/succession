use strict;
use warnings;

BEGIN { $ENV{SUCC_CACHE_DRIVER} = 'Null' }

use Cwd qw(getcwd);
use Digest::SHA qw(sha256_hex);
use File::Temp ();
use FindBin qw($RealBin);
use IPC::Open3;
use Path::Tiny qw(path);
use Symbol qw(gensym);
use Test::More;

my $root = path($RealBin)->parent(2);
my $script = $root->child('bin', 'export_print');
my $dir = File::Temp->newdir;
ok(-x $script, 'export_print is executable');

my ($svg, $svg_err, $svg_exit) = run_cmd('--format', 'svg', '1962-09-07');
is($svg_exit, 0, 'SVG export succeeds');
is($svg_err, '', 'SVG export has no stderr output');
like($svg, qr{<svg .*width="297mm" height="420mm"}, 'SVG export is A3 artwork');
like($svg, qr{7 September 1962}, 'SVG export uses the selected date');
unlike($svg, qr{SPECIMEN}, 'SVG export is unwatermarked');

my ($png, $png_err, $png_exit) = run_cmd('1962-09-07');
is($png_exit, 0, 'default PNG export succeeds');
is($png_err, '', 'PNG export has no stderr output');
is(substr($png, 0, 8), "\x89PNG\r\n\x1a\n", 'default output is actual PNG bytes');
is_deeply([unpack('NN', substr($png, 16, 8))], [3508, 4961], 'PNG is A3 at 300 dpi');
my $svg_path = path("$dir", 'clean.svg');
my $png_path = path("$dir", 'expected.png');
$svg_path->spew_raw($svg);
system('rsvg-convert', '--dpi-x', '300', '--dpi-y', '300',
  '--output', "$png_path", "$svg_path") == 0 or die 'Unable to prepare clean PNG comparison';
is(sha256_hex($png), sha256_hex($png_path->slurp_raw),
  'PNG is the direct rasterisation of the unwatermarked SVG');

my $file = path("$dir", 'saved print.png');
my ($out, $err, $exit) = run_cmd('--format', 'png', '--output', "$file", '1962-09-07');
is($exit, 0, 'explicit PNG file export succeeds');
is($out, '', 'file export leaves stdout empty');
is(sha256_hex($file->slurp_raw), sha256_hex($png),
  'file export preserves all PNG bytes, including a path containing spaces');

my ($birth_svg, undef, $birth_exit) = run_cmd('--format', 'svg', '--order', 'birth', '1962-09-07');
is($birth_exit, 0, 'birth ordering is supported');
like($birth_svg, qr{The Prince Charles.*The Princess Anne.*The Prince Andrew}s,
  'birth order is reflected in the artwork');
like($svg, qr{The Prince Charles.*The Prince Andrew.*The Princess Anne}s,
  'default ordering follows succession');

{
  local $ENV{SUCC_DSN};
  local $ENV{SUCC_DB_PATH};
  delete @ENV{qw(SUCC_DSN SUCC_DB_PATH)};
  my $original = getcwd;
  chdir "$dir" or die "Unable to change directory: $!";
  my ($outside_svg, $outside_err, $outside_exit) = run_cmd('--format', 'svg', '--output', '-', '1962-09-07');
  chdir $original or die "Unable to restore directory: $!";
  is($outside_exit, 0, 'export finds its library and default database outside the checkout');
  is($outside_err, '', 'export outside the checkout has no stderr output');
  like($outside_svg, qr{7 September 1962}, '--output - writes SVG to stdout');
}

my ($help, undef, $help_exit) = run_cmd('--help');
is($help_exit, 0, 'help succeeds without a date');
like($help, qr{Usage: export_print}, 'help describes the command');

{
  my $tools = path("$dir", 'tools')->mkdir;
  my $converter = $tools->child('rsvg-convert');
  $converter->spew_raw("#!/bin/sh\nexit 1\n");
  chmod 0755, "$converter" or die "Unable to make test converter executable: $!";
  local $ENV{PATH} = "$tools:$ENV{PATH}";
  my $existing = path("$dir", 'existing.png');
  $existing->spew_raw('existing artwork');
  my ($out, $err, $exit) = run_cmd('--output', "$existing", '1962-09-07');
  isnt($exit, 0, 'PNG conversion failure fails the command');
  is($out, '', 'PNG conversion failure emits no partial artwork');
  like($err, qr/Unable to convert SVG to PNG/, 'PNG conversion failure is explained');
  is($existing->slurp_raw, 'existing artwork', 'conversion failure preserves an existing output file');
}

for my $case (
  [ [], qr/Usage:/ ],
  [ ['--format', 'jpeg', '1962-09-07'], qr/--format must be svg or png/ ],
  [ ['--order', 'unknown', '1962-09-07'], qr/--order must be succession or birth/ ],
  [ ['1962/09/07'], qr/valid YYYY-MM-DD date/ ],
  [ ['1962-02-30'], qr/valid YYYY-MM-DD date/ ],
  [ ['1819-12-31'], qr/between 1820-01-29 and today/ ],
  [ ['9999-01-01'], qr/between 1820-01-29 and today/ ],
  [ ['1962-09-07', 'extra'], qr/Usage:/ ],
) {
  my ($args, $message) = @$case;
  my ($out, $err, $exit) = run_cmd(@$args);
  isnt($exit, 0, "invalid invocation fails: @$args");
  is($out, '', 'invalid invocation emits no partial artwork');
  like($err, $message, 'invalid invocation explains the problem');
}

done_testing();

sub run_cmd {
  my $err = gensym;
  my $pid = open3(my $in, my $out, $err, $^X, "$script", @_);
  close $in;
  binmode $out, ':raw';
  binmode $err, ':raw';
  local $/;
  my $stdout = <$out> // '';
  my $stderr = <$err> // '';
  waitpid $pid, 0;
  return ($stdout, $stderr, $? >> 8);
}
