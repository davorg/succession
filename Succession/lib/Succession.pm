package Succession;
use Dancer2;
use Try::Tiny;

use Succession::App;
use Succession::Request;

our $VERSION = '0.1.1';

hook before => sub {
  bless request, 'Succession::Request';

  vars->{app} = Succession::App->new(
    request => request,
  );
  vars->{dancer_app} = app;
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

true;
