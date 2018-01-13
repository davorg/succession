package Succession;
use Dancer2;

use Succession::App;

our $VERSION = '0.1';

get qr{/(\d{4}-\d\d-\d\d)?} => sub {
  my ($date) = splat;
  my $app = Succession::App->new($date // ());

  template 'index', {
    date       => $app->date,
    sovereign  => $app->sovereign,
    succession => $app->succession,
  };
};



true;
