package Succession;
use Dancer2;

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

  my $date_err;

  if (defined $date and $date !~ /^\d{4}-\d\d-\d\d$/) {
    $date_err = 'Date must be in the format YYYY-MM-DD';
    $date = undef;
  }

  if (defined $date and not Succession::App->is_valid_date($date)) {
    $date_err = "$date is not a valid date";
    $date = undef;
  }

  my $args = {
    request => request,
  };
  $args->{date} = $date if defined $date;

  my $app = Succession::App->new($args);

  if ($app->too_early) {
    $date_err = 'Date cannot be before ' .
      $app->earliest->strftime('%d %B %Y');
  }
  if ($app->too_late) {
    $date_err = 'Date cannot be after today';
  }

  if ($date_err) {
    var date_err => $date_err;
    send_error $date_err, 404;
  }

  template 'index', {
    app     => $app,
    # changes => $app->get_changes,
    error   => $date_err,
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

true;
