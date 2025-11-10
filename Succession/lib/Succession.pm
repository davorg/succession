package Succession;
use Dancer2;
use Try::Tiny;

use Succession::App;
use Succession::Request;

our $VERSION = '0.1';

hook before => sub {
  bless request, 'Succession::Request';

  vars->{app} = Succession::App->new(
    request => request,
  );

  warn vars->{app}->model->db_ver;
};

get '/db' => sub {
  return vars->{app}->model->db_ver;
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
    dates => $app->model->get_anniveraries,
  };
};

get qr{/(\d{4}-\d\d-\d\d)?$} => sub {
  set layout => 'main';

  my ($date) = splat;
  $date //= query_parameters->get('date');

  my ($app, $date_err) = make_app({
    date => $date,
    request => request,
  });

  if ($date_err) {
    if ($date_err =~ /before/) {
      $date_err .= Succession::App->new->earliest->strftime('%d %B %Y');
    }
    var date_err => $date_err;
    send_error $date_err, 404;
  }

  template 'index', {
    app     => $app,
  };
};

get qr{/p/(.*)} => sub {
  set layout => 'main';

  my ($slug) = splat;

  my $person = request->person;

  unless ($person) {
    send_error "'$slug' is not a valid person identifier", 404;
    return;
  }

warn "Serving person page for ", $person->name, "\n";

  template 'person', {
    app    => vars->{app},
    person => $person,
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

  my ($app, $date_err) = make_app({
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

  my $app = try {
    Succession::App->new($args)
  } catch {
    if (/Validation failed/) {
      $date_err = 'Dates must be in the format: YYYY-MM-DD';
    } elsif (/Date cannot be before/) {
      $date_err = 'Date cannot be before ';
    } elsif (/Date cannot be after today/) {
      $date_err = 'Date cannot be after today';
    }
  };

  return ($app, $date_err);
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
