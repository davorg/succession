use strict;
use warnings;

use Test::More;
use DateTime;
use JSON::MaybeXS qw[decode_json];
use IPC::Open3;
use Symbol qw[gensym];

use Succession::Model;

my $repo_root = '/home/runner/work/succession/succession';
my $script    = "$repo_root/bin/succession_tree";
my $lib_path  = "$repo_root/Succession/lib";
my $db_path   = "$repo_root/data/los.sqlite";

$ENV{SUCC_DB_PATH} = $db_path;

ok(-x $script, 'succession_tree script exists and is executable');

my $model = Succession::Model->new;
my $date  = DateTime->today;
my $sov   = $model->sovereign_on_date($date);

my ($ok_out, $ok_err, $ok_exit) = run_cmd(
  $^X, "-I$lib_path", $script, $sov->id, $date->ymd
);

is($ok_exit, 0, 'script exits successfully with valid arguments');
is($ok_err, '', 'script has no stderr output on success');

my $tree = eval { decode_json($ok_out) };
ok(!$@, 'script outputs valid JSON');
is($tree->{name}, $sov->person->name_on_date($date), 'JSON root matches selected sovereign');
ok(exists $tree->{children}, 'JSON contains children field');

my (undef, $usage_err, $usage_exit) = run_cmd($^X, "-I$lib_path", $script);
ok($usage_exit != 0, 'script fails without required arguments');
like($usage_err, qr/Usage: .*succession_tree sovereign_id YYYY-MM-DD/, 'usage message is shown');

my (undef, $date_err, $date_exit) = run_cmd(
  $^X, "-I$lib_path", $script, $sov->id, '2026/01/01'
);
ok($date_exit != 0, 'script fails with invalid date');
like($date_err, qr/Date must be in YYYY-MM-DD format/, 'invalid date message is shown');

done_testing();

sub run_cmd {
  my @cmd = @_;
  my $err = gensym;
  my $pid = open3(my $in, my $out, $err, @cmd);
  close $in;

  local $/;
  my $stdout = <$out> // '';
  my $stderr = <$err> // '';

  waitpid $pid, 0;
  my $exit = $? >> 8;

  return ($stdout, $stderr, $exit);
}
