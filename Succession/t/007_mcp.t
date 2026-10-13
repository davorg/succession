use strict;
use warnings;

BEGIN { $ENV{SUCC_CACHE_DRIVER} = 'Null' }

use Test::More;
use DateTime;
use Digest::SHA qw(sha256_hex);
use HTTP::Request::Common;
use JSON::MaybeXS qw(decode_json);
use Path::Tiny qw[path];
use Plack::Test;

use Succession;
use Succession::MCP;

{
  package Local::Person;
  sub new  { bless $_[1], $_[0] }
  sub name { $_[0]->{name} }
  sub born { $_[0]->{born} }
  sub slug { $_[0]->{slug} }
}

{
  package Local::Sovereign;
  sub new    { bless $_[1], $_[0] }
  sub person { $_[0]->{person} }
}

{
  package Local::Model;
  sub new { bless { last_limit => undef }, $_[0] }
  sub sovereign_on_date {
    my ($self, $date) = @_;
    return Local::Sovereign->new({
      person => Local::Person->new({
        name => 'Test Sovereign',
        born => DateTime->new(year => 1970, month => 1, day => 1),
        slug => 'test-sovereign',
      }),
    });
  }
  sub get_succession_data {
    my ($self, $date, $limit) = @_;
    $self->{last_limit} = $limit;
    return {
      sovereign  => { name => 'Test Sovereign' },
      successors => [ map { { number => $_, name => "Person $_" } } 1 .. 2 ],
    };
  }
  sub last_limit { $_[0]->{last_limit} }
}

my $mcp = Succession::MCP->new(
  server_version => 'test-version',
  tools_file     => path($0)->parent->parent->child('public', 'mcp-tools.yml')->stringify,
);

my $init = $mcp->initialize_data;
is($init->{serverInfo}{version}, 'test-version', 'Server version returned in initialize data');

my $tools = $mcp->tools;
ok(@$tools > 0, 'Tools loaded from YAML');
ok(defined $mcp->tool_docs->[0]{input_schema_json}, 'Tool docs include JSON schema text');

my $error = $mcp->call_tool(params => { name => 'unknown' }, model => Local::Model->new);
ok($error->{isError}, 'Unknown tool returns MCP error');

my $model = Local::Model->new;
my $result = $mcp->call_tool(
  params => {
    name      => 'line_of_succession',
    arguments => { date => '2020-01-01', limit => 200 },
  },
  model => $model,
);
is($model->last_limit, 30, 'Line of succession tool caps limit at 30');
is($result->{structuredContent}{sovereign}{name}, 'Test Sovereign', 'Tool returns model data');

my $sov_result = $mcp->call_tool(
  params => {
    name      => 'sovereign_on_date',
    arguments => { date => '2020-01-01' },
  },
  model => Local::Model->new,
);
is($sov_result->{structuredContent}{sovereign}{slug}, 'test-sovereign',
  'Sovereign tool returns person slug');

ok($mcp->mcp_date('2020-01-01'), 'Valid date accepted');
ok(!$mcp->mcp_date('not-a-date'), 'Invalid date rejected');

my $rpc = $mcp->rpc_result(7, { ok => 1 });
is($rpc->{id}, 7, 'rpc_result includes id');
is($rpc->{result}{ok}, 1, 'rpc_result includes payload');

my $rpc_error = $mcp->rpc_error(9, -1, 'oops');
is($rpc_error->{error}{code}, -1, 'rpc_error includes error code');

{
  no warnings 'redefine';
  local *Succession::Model::get_feed_entries = sub { [] };

  my $test = Plack::Test->create(Succession->to_app);
  my $page = $test->request(GET '/mcp');
  ok($page->is_success, 'MCP documentation page loads');
  like($page->decoded_content, qr{<h1>Line of Succession MCP Server</h1>},
    'MCP documentation content renders');
  my ($css_url, $digest) = $page->decoded_content =~
    m{href="(/css/style\.css\?v=([a-f0-9]{16}))"};
  ok($css_url, 'MCP documentation uses the fingerprinted local stylesheet');
  my $css = $test->request(GET($css_url // '/css/style.css'));
  ok($css->is_success, 'MCP stylesheet URL serves CSS');
  is($digest, substr(sha256_hex($css->content), 0, 16),
    'MCP stylesheet fingerprint matches the served file');
  like($page->decoded_content, qr{href="/r/how-many-people-are-in-the-line-of-succession"},
    'MCP documentation includes the reference menu');

  my $response = $test->request(POST '/mcp',
    Content_Type => 'application/json',
    Content => '{"jsonrpc":"2.0","id":7,"method":"initialize"}');
  is($response->code, 200, 'MCP initialize POST still succeeds');
  is(decode_json($response->content)->{result}{serverInfo}{version}, $Succession::VERSION,
    'MCP initialize returns the application version');
  unlike($response->content, qr{<!doctype html|<html}, 'MCP POST omits the HTML layout');

  my $stream = $test->request(GET '/mcp', Accept => 'text/event-stream');
  is($stream->code, 405, 'MCP GET still rejects SSE requests');
  is($stream->header('Allow'), 'POST', 'SSE response directs clients to POST');
}

done_testing();
