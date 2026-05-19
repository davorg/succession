package Succession;

use strict;
use warnings;
use feature 'state';

use Dancer2;
use Try::Tiny;
use Text::Markdown 'markdown';
use Path::Tiny;
use DateTime;
use YAML::XS qw[LoadFile];
use Path::Tiny qw[path];
use FindBin qw[$Bin];
use Succession::App;
use Succession::Request;

our $VERSION = '0.9.0';

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

  my ($slug) = splat;

  my $md_file = path(setting('appdir'), 'reference', "$slug.md");

  if (!$md_file->is_file) {
    status 404;
    return template '404', { app => vars->{app} };
  }

  my ($title, $body) = _parse_frontmatter($md_file->slurp_utf8);
  my $html = markdown($body);

  template 'reference', {
    app     => vars->{app},
    content => $html,
    title   => $title,
  };
};

get '/shop' => sub {
  set layout => 'main';

  my $app = vars->{app};

  my ($shop, $etag, $last_mod) = $app->model->get_shop_data;

  return '' if handle_conditional_get($etag, $last_mod);

  response_header 'ETag'          => $etag;
  response_header 'Last-Modified' => $last_mod;
  response_header 'Cache-Control' => 'public, max-age=300';

  template 'shop' => {
    title => 'Shop',
    shop  => $shop,
    amazon_tag => setting('amazon_tag') // 'davblog-21',
    app   => $app,
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
  template 'mcp' => {
    tools => _mcp_tool_docs(),
  };
};

sub _mcp_tool_docs {
  state $tools = LoadFile("$Bin/../public/mcp-tools.yml");
  return [
    map {
      +{
        $_->%*,
        input_schema_json => to_json($_->{inputSchema}, { pretty => 1 }),
      }
    } $tools->@*
  ];
}

post '/mcp' => sub {
  content_type 'application/json';

  my $req = eval { from_json(request->body) };

  if ($@ or ref $req ne 'HASH') {
    return to_json(_mcp_error(undef, -32700, 'Parse error'));
  }

  my $id     = $req->{id};
  my $method = $req->{method} // '';

  return '' unless exists $req->{id}; # JSON-RPC notification

  if ($method eq 'initialize') {
    return(to_json(_mcp_result($id, {
      protocolVersion => '2025-11-25',
      capabilities    => {
        tools => {},
      },
      serverInfo => {
        name    => 'line-of-succession',
        version => $Succession::VERSION,
      },
    })));
  }

  if ($method eq 'tools/list') {
    return to_json(_mcp_result($id, {
      tools => _mcp_tools(),
    }));
  }

  if ($method eq 'tools/call') {
    return to_json(_mcp_result(
      $id,
      _mcp_call_tool($req->{params} // {}),
    ));
  }

  return to_json(_mcp_error($id, -32601, 'Method not found'));
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

  if (my $error = vars->{app}->error) {
    cookie 'error' => $error;
    redirect '/';
    return;
  }

  template 'person', {
    app    => vars->{app},
    person => request->person,
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

get '/api' => sub {
  set layout => '';
  # set serializer => '';

  my $date  = query_parameters->get('date');
  my $count = query_parameters->get('count');
  my $callback = query_parameters->get('callback');

  my $app = make_app({
    date => $date,
    list_size => $count,
    request => request,
  });

  my $succ = $app->get_succession_data($app->date, $app->list_size);

  return "$callback(" . encode_json($succ) . ')';
};

sub make_app {
  my ($params) = @_;

  my $args = {
    request => $params->{request},
  };

  for (qw[date list_size]) {
    $args->{$_} = $params->{$_} if defined $params->{$_};
  }

  my $date_err;

  my $app = Succession::App->new($args);
 
  return $app;
}

sub handle_conditional_get {
  my ($etag, $last_mod) = @_;

  my $if_none_match = request->header('If-None-Match');
  my $if_modified   = request->header('If-Modified-Since');

  if (defined $if_none_match && $if_none_match eq $etag) {
    status 304;
    response_header 'ETag'          => $etag;
    response_header 'Last-Modified' => $last_mod;
    response_header 'Cache-Control' => 'public, max-age=300';
    return 1;
  }

  if (defined $if_modified && $if_modified eq $last_mod) {
    status 304;
    response_header 'ETag'          => $etag;
    response_header 'Last-Modified' => $last_mod;
    response_header 'Cache-Control' => 'public, max-age=300';
    return 1;
  }

  return 0;
}

sub _parse_frontmatter {
  my ($content) = @_;
  my $title;

  if ($content =~ /\A---\n(.*?)\n---\n/s) {
    my $fm = $1;
    ($title) = $fm =~ /^title:\s*(.+?)\s*$/m;
    $content =~ s/\A---\n.*?\n---\n//s;
  }

  return ($title, $content);
}

sub _mcp_tools {
  warn "Loading MCP tools from YAML file...[$Bin/../public/mcp-tools.yml]\n";
  state $tools = LoadFile("$Bin/../public/mcp-tools.yml");

  return [
    map {
      {
        name        => $_->{name},
        description => $_->{description},
        inputSchema => $_->{inputSchema},
      }
    } $tools->@*
  ];
}

sub _mcp_call_tool {
  my ($params) = @_;

  my $name = $params->{name} // '';
  my $args = $params->{arguments} // {};

  return _mcp_tool_error("Unknown tool: $name")
    unless $name eq 'sovereign_on_date'
        || $name eq 'line_of_succession';

  my $date;

  if (exists $args->{date}) {
    $date = _mcp_date($args->{date});
    unless ($date) {
      return _mcp_tool_error('Invalid date format. Use YYYY-MM-DD.');
    }
  } else {
    $date = DateTime->today;
  }

  my $model = vars->{app}->model;

  if ($name eq 'sovereign_on_date') {
    my $sov    = $model->sovereign_on_date($date);
    my $person = $sov->person;

    my $data = {
      date      => $date->ymd,
      sovereign => {
        name => $person->name,
        born => $person->born ? $person->born->ymd : undef,
        slug => $person->slug,
      },
    };

    my $text = "On " . $date->ymd . ", the sovereign was " . $person->name;

    return _mcp_tool_result($data, $text);
  }

  if ($name eq 'line_of_succession') {
    my $limit = $args->{limit} // 30;
    $limit = 1   if $limit < 1;
    $limit = 100 if $limit > 100;

    my $data = $model->get_succession_data($date, $limit);

    my $text = "Line of succession on " . $date->ymd . ":\nSovereign: " .
               $data->{sovereign}->{name} . "\n" .
               join("\n", map { "$_->{number}. $_->{name}" } @{ $data->{successors} });

    return _mcp_tool_result($data, $text);
  }
}

sub _mcp_date {
  my ($date) = @_;
  return unless defined $date;
  return unless $date =~ /\A(\d{4})-(\d\d)-(\d\d)\z/;

  return eval {
    DateTime->new(
      year  => $1,
      month => $2,
      day   => $3,
    );
  };
}

sub _mcp_tool_result {
  my ($data, $text) = @_;

  $text //= encode_json($data);

  return {
    content => [{
      type => 'text',
      text => $text,
    }],
    structuredContent => $data,
  };
}

sub _mcp_tool_error {
  my ($message) = @_;

  return {
    isError => JSON::MaybeXS::true,
    content => [{
      type => 'text',
      text => $message,
    }],
  };
}

sub _mcp_result {
  my ($id, $result) = @_;

  return {
    jsonrpc => '2.0',
    id      => $id,
    result  => $result,
  };
}

sub _mcp_error {
  my ($id, $code, $message) = @_;

  return encode_json({
    jsonrpc => '2.0',
    id      => $id,
    error   => {
      code    => $code,
      message => $message,
    },
  });
}

true;
