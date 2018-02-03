package Succession;
use Dancer2;

use Succession::App;

our $VERSION = '0.1';

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

  if (defined $date and !Succession::App->is_valid_date($date)) {
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
    changes => $app->get_changes,
    error   => $date_err,
  };
};



true;
