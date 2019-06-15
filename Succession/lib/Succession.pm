package Succession;
use Dancer2;

use Succession::App;

our $VERSION = '0.1';

get '/dates' => sub {
  my $app = Succession::App->new;

  template 'dates', {
    app => $app,
    feed    => $app->feed,
  };
};

get qr{/(\d{4}-\d\d-\d\d)?$} => sub {
  my ($date) = splat;

  my $date_err;

  unless ($date) {
    my $p = query_parameters;
    $date = $p->get('date');
  }

  if (defined $date and $date !~ /^\d{4}-\d\d-\d\d$/) {
    $date_err = 'Date must be in the format YYYY-MM-DD';
    $date = undef;
  }

  if (defined $date and not Succession::App->is_valid_date($date)) {
    $date_err = "$date is not a valid date";
    $date = undef;
  }

  my $app = Succession::App->new($date // ());

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
    feed    => $app->feed,
    # changes => $app->get_changes,
    error   => $date_err,
  };
};

get qr{/p/(.*)} => sub {
  my ($slug) = splat;

  my $app    = Succession::App->new;
warn "calling get_person_from_slug: $slug\n";
  my $person = $app->model->get_person_from_slug($slug);

  template 'person', {
    app    => $app,
    person => $person,
  };
};

true;
