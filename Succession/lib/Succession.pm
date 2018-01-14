package Succession;
use Dancer2;

use Succession::App;

our $VERSION = '0.1';

get qr{/(\d{4}-\d\d-\d\d)?$} => sub {
  my ($date) = splat;

  unless ($date) {
    my $p = query_parameters;
    $date = $p->get('date');
  }

  my $app = Succession::App->new($date // ());

  my $date_err;
  if ($app->too_early) {
    $date_err = 'Date cannot be before ' .
      $app->earliest->strftime('%d %B %Y');
  }
  if ($app->too_late) {
    $date_err = 'Date cannot be after today';
  }

  if ($date_err) {
    $app = Succession::App->new;
  }

  template 'index', {
    app   => $app,
    error => $date_err,
  };
};



true;
