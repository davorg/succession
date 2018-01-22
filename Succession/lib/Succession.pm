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

  my $app = Succession::App->new($date // ());

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
