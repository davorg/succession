package Succession;

use strict;
use warnings;
use feature 'state';

use Dancer2;
use JSON::MaybeXS ();
use DateTime;
use Text::Markdown 'markdown';
use Path::Tiny;
use Path::Tiny qw[path];
use URI::Escape qw(uri_escape_utf8);
use Succession::App;
use Succession::MCP;
use Succession::Request;
use Succession::RouteHelpers;
use Succession::Print;

our $VERSION = '0.13.1';

hook before => sub {
  bless request, 'Succession::Request';

  vars->{app} = Succession::App->new(
    request => request,
  );
  vars->{dancer_app} = app;
};

hook before_template_render => sub {
  my ($tokens) = @_;
  return unless $tokens->{app};
  my $ref_dir = path(setting('appdir'), 'reference');
  $tokens->{ref_menu} = $tokens->{app}->model->get_reference_menu($ref_dir);
};

get '/print.svg' => sub {
  # Preserve old preview links without exposing downloadable vector artwork.
  my @params;
  for my $key (qw(date sovereign_id size order)) {
    my $value = query_parameters->get($key);
    push @params, "$key=" . uri_escape_utf8($value) if defined $value;
  }
  redirect '/print.png' . (@params ? '?' . join('&', @params) : '');
};

get '/print.png' => sub {
  my $app = vars->{app};
  my $date_str = query_parameters->get('date') // '';
  my $sovereign_id = query_parameters->get('sovereign_id') // '';
  my $size = query_parameters->get('size') // 'A3';
  my $order = query_parameters->get('order') // 'succession';
  my $bad_request = sub {
    status 400;
    content_type 'text/plain';
    return $_[0] . "\n";
  };

  my $date;
  if ($date_str =~ /\A([0-9]{4})-([0-9]{2})-([0-9]{2})\z/) {
    $date = eval { DateTime->new(year => $1, month => $2, day => $3) };
  }
  return $bad_request->('date must be a valid YYYY-MM-DD date') unless $date;
  return $bad_request->('date must be between ' . $app->earliest->ymd . ' and today')
    if $date < $app->earliest || $date > DateTime->today;
  return $bad_request->('sovereign_id must be a positive integer')
    unless $sovereign_id =~ /\A[1-9][0-9]*\z/;
  return $bad_request->('Only size=A3 is currently supported') unless $size eq 'A3';
  return $bad_request->('order must be birth or succession')
    unless $order eq 'birth' || $order eq 'succession';

  my $tree = eval { $app->model->succession_tree($sovereign_id, $date, $order) };
  if (my $error = $@) {
    return $bad_request->('Unknown sovereign_id') if $error =~ /\AUnknown sovereign id:/;
    return $bad_request->('The root monarch must be reigning or deceased on the selected date')
      if $error =~ /\ASovereign must be current on date or be dead/;
    die $error;
  }

  my $svg = Succession::Print->render(data => $tree, date => $date, size => $size);
  unless (defined $svg) {
    status 422;
    content_type 'text/plain';
    return "This hierarchy is too large for the current A3 layout; choose a more recent root monarch.\n";
  }
  my $png = Succession::Print->preview_png($svg);
  content_type 'image/png';
  response_header 'Content-Disposition' => qq{inline; filename="succession-$date_str-specimen.png"};
  return $png;
};

get '/info' => sub {
  my %info = (
    perl_version   => $],
    dancer_version => $Dancer2::VERSION,
    succession_version => $Succession::VERSION,
    db_version    => vars->{app}->model->db_ver,
    environment  => vars->{dancer_app}->environment,
    host         => vars->{app}->host,
    cache        => vars->{app}->model->cache->short_driver_name,
  );

  my $info_str = join "\n", map { "* $_: $info{$_}" } sort keys %info;

  content_type 'text/plain';

  return $info_str;
};

get '/lp' => sub {
  set layout => 'main';

  template 'lp', {
    app => vars->{app},
  };
};

get qr{/r/([\w-]+)$} => sub {
  set layout => 'main';
  state $helpers = Succession::RouteHelpers->new;

  my ($slug) = splat;

  my $md_file = path(setting('appdir'), 'reference', "$slug.md");

  if (!$md_file->is_file) {
    status 404;
    return template '404', { app => vars->{app} };
  }

  my ($title, $body) = $helpers->parse_frontmatter($md_file->slurp_utf8);
  my $html = markdown($body);

  template 'reference', {
    app     => vars->{app},
    content => $html,
    title   => $title,
  };
};

get '/shop' => sub {
  set layout => 'main';
  state $helpers = Succession::RouteHelpers->new;

  my $app = vars->{app};

  my $shop_path = path(setting('appdir'), 'public', 'var', 'shop.json');
  my ($shop, $etag, $last_mod) = $app->model->get_shop_data($shop_path);

  if ($helpers->is_not_modified(request, $etag, $last_mod)) {
    status 304;
    response_header 'ETag'          => $etag;
    response_header 'Last-Modified' => $last_mod;
    response_header 'Cache-Control' => 'public, max-age=300';
    return '';
  }

  response_header 'ETag'          => $etag;
  response_header 'Last-Modified' => $last_mod;
  response_header 'Cache-Control' => 'public, max-age=300';

  my $amazon_tag = setting('amazon_tag') // 'davblog-21';
  my $amazon_tag_json = JSON::MaybeXS->new(allow_nonref => 1)->encode($amazon_tag);
  $amazon_tag_json =~ s/</\\u003c/g;
  $amazon_tag_json =~ s/>/\\u003e/g;
  $amazon_tag_json =~ s/&/\\u0026/g;

  template 'shop' => {
    title           => 'Shop',
    shop            => $shop,
    amazon_tag      => $amazon_tag,
    amazon_tag_json => $amazon_tag_json,
    amazon_tag_url  => uri_escape_utf8($amazon_tag),
    app             => $app,
  };
};

get '/dates' => sub {
  set layout => 'main';

  template 'dates', {
    app => vars->{app},
  };
};

get '/anniversaries' => sub {
  set layout => 'main';

  my $app = vars->{app};

  template 'anniversaries', {
    app   => $app,
    dates => $app->model->get_anniversaries,
  };
};

get '/mcp' => sub {
  state $mcp = Succession::MCP->new(
    server_version => $Succession::VERSION,
    tools_file     => path(setting('appdir'), 'public', 'mcp-tools.yml')->stringify,
  );

  template 'mcp' => {
    tools => $mcp->tool_docs,
  };
};

post '/mcp' => sub {
  state $mcp = Succession::MCP->new(
    server_version => $Succession::VERSION,
    tools_file     => path(setting('appdir'), 'public', 'mcp-tools.yml')->stringify,
  );

  content_type 'application/json';

  my $req = eval { from_json(request->body) };

  if ($@ or ref $req ne 'HASH') {
    return to_json($mcp->rpc_error(undef, -32700, 'Parse error'));
  }

  my $id     = $req->{id};
  my $method = $req->{method} // '';

  return '' unless exists $req->{id}; # JSON-RPC notification

  if ($method eq 'initialize') {
    return to_json($mcp->rpc_result($id, $mcp->initialize_data));
  }

  if ($method eq 'tools/list') {
    return to_json($mcp->rpc_result($id, {
      tools => $mcp->tools,
    }));
  }

  if ($method eq 'tools/call') {
    return to_json($mcp->rpc_result(
      $id,
      $mcp->call_tool(
        params => ($req->{params} // {}),
        model  => vars->{app}->model,
      ),
    ));
  }

  return to_json($mcp->rpc_error($id, -32601, 'Method not found'));
};

get qr{/(\d{4}-\d\d-\d\d)?$} => sub {
  set layout => 'main';

  my $app = vars->{app};

  if (my $error = $app->error) {
    cookie 'error' => $error;
    redirect '/';
    return;
  }

  my $error;
  if ($error = cookie 'error') {
    cookie 'error' => 'expired', expires => '-1d';
  }

  template 'index', {
    app     => $app,
    error   => $error,
  };
};

get qr{/p/(.*)} => sub {
  set layout => 'main';

  my $app = vars->{app};

  if (my $error = $app->error) {
    cookie 'error' => $error;
    redirect '/';
    return;
  }

  my $person = request->person;

  template 'person', {
    app    => $app,
    person => $person,
    %{ $app->model->get_person_page_data($person) },
  };
};

get '/changes' => sub {
  set layout => 'main';

  my $app = vars->{app};

  my $changes = $app->model->get_all_changes;

  template 'changes', {
    app => $app,
    changes => $changes,
  }
};

# Experimental API spike. Keep this out of the production route table until
# its interface and Succession::App integration have been completed.
#
# get '/api' => sub {
#   set layout => '';
#   # set serializer => '';
#   state $helpers = Succession::RouteHelpers->new;
#
#   my $date  = query_parameters->get('date');
#   my $count = query_parameters->get('count');
#   my $callback = query_parameters->get('callback');
#
#   my $app = $helpers->make_app({
#     date => $date,
#     list_size => $count,
#     request => request,
#   });
#
#   my $succ = $app->get_succession_data($app->date, $app->list_size);
#
#   return "$callback(" . encode_json($succ) . ')';
# };

true;
