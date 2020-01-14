package Succession;
use Dancer2;
use Try::Tiny;

use Succession::App;

our $VERSION = '0.1';

get '/dates' => sub {
  my $app = Succession::App->new({
    request => request,
  });

  template 'dates', {
    app => $app,
  };
};

get qr{/(\d{4}-\d\d-\d\d)?$} => sub {
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
  my ($slug) = splat;

  my $app    = Succession::App->new({
    request => request,
  });
  my $person = $app->model->get_person_from_slug($slug);
  $app->person($person);

  template 'person', {
    app    => $app,
    person => $person,
  };
};

get '/changes' => sub {
  my $app = Succession::App->new({
    request => request,
  });

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

true;
