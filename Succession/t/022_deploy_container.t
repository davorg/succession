use strict;
use warnings;

use Cwd qw(abs_path);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use IPC::Open3 qw(open3);
use Symbol qw(gensym);
use Test::More;

sub run_bash {
  my ($cmd) = @_;
  my $stderr = gensym;
  my $pid = open3(undef, my $stdout, $stderr, 'bash', '-c', $cmd);
  my $out = do { local $/; <$stdout> // '' };
  my $err = do { local $/; <$stderr> // '' };
  waitpid $pid, 0;
  return ($? >> 8, $out, $err);
}

my $repo_root = abs_path('.');
my $script = "$repo_root/bin/deploy_container";

my $tmp = tempdir(CLEANUP => 1);
my $fake_bin = "$tmp/bin";
make_path($fake_bin);
my $deploy_log = "$tmp/gcloud-deploy.log";

open my $fh, '>', "$fake_bin/gcloud" or die $!;
print {$fh} <<"GCLOUD";
#!/usr/bin/env bash
set -euo pipefail
case "\${1:-}" in
  artifacts)
    printf '%s\\n' "\${GCLOUD_ARTIFACT_TAGS:-v0.11.2}"
    ;;
  run)
    if [[ -n "\${GCLOUD_DEPLOY_LOG:-}" ]]; then
      printf '%s\\n' "\$@" > "\${GCLOUD_DEPLOY_LOG}"
    fi
    ;;
esac
GCLOUD
close $fh;
chmod 0755, "$fake_bin/gcloud" or die $!;

my ($missing_exit, $missing_out, $missing_err) = run_bash(
  "cd '$repo_root' && PATH=\"$fake_bin:\$PATH\" '$script'"
);
isnt($missing_exit, 0, 'deploy_container fails without a version');
like($missing_err . $missing_out, qr/Usage: .*deploy_container <version>/, 'usage is shown when version is missing');

my ($invalid_exit, $invalid_out, $invalid_err) = run_bash(
  "cd '$repo_root' && PATH=\"$fake_bin:\$PATH\" '$script' invalid"
);
isnt($invalid_exit, 0, 'deploy_container fails with an invalid version');
like($invalid_err . $invalid_out, qr/is not valid/, 'invalid version is rejected');

my ($missing_tag_exit, $missing_tag_out, $missing_tag_err) = run_bash(
  "cd '$repo_root' && GCLOUD_ARTIFACT_TAGS='v0.11.2' PATH=\"$fake_bin:\$PATH\" '$script' v0.11.3"
);
isnt($missing_tag_exit, 0, 'deploy_container fails if version tag is missing from Artifact Registry');
like($missing_tag_err . $missing_tag_out, qr/was not found in Artifact Registry/, 'missing version tag is rejected');

my ($ok_exit, $ok_out, $ok_err) = run_bash(
  "cd '$repo_root' && GCLOUD_ARTIFACT_TAGS='v0.11.2' GCLOUD_DEPLOY_LOG='$deploy_log' PATH=\"$fake_bin:\$PATH\" " .
  "PROJECT_ID=test-proj REGION=test-region REPO=test-repo IMAGE_NAME=test-image " .
  "SERVICE_NAME=test-service VPC_CONNECTOR=test-connector SUCC_DSN='dbi:SQLite:dbname=/tmp/test.sqlite' " .
  "'$script' v0.11.2"
);
is($ok_exit, 0, 'deploy_container accepts a valid version and runs deploy');
is($ok_err, '', 'no stderr for successful run');

open my $log_fh, '<', $deploy_log or die $!;
my $log = do { local $/; <$log_fh> // '' };
close $log_fh;

like(
  $log,
  qr/--image=test-region-docker\.pkg\.dev\/test-proj\/test-repo\/test-image:v0\.11\.2/,
  'deploy uses the version tag as image reference',
);
like(
  $log,
  qr/SUCC_VERSION=0\.11\.2/,
  'deploy passes SUCC_VERSION from the supplied version',
);

done_testing();
