use strict;
use warnings;

BEGIN {
  $ENV{SUCC_CACHE_DRIVER} = 'Null';
}

use HTTP::Request::Common;
use Plack::Test;
use Scalar::Util qw(weaken);
use Test::More;

use Succession;

my (@apps, @models);
my $app_constructor   = Succession::App->can('new');
my $model_constructor = Succession::Model->can('new');

{
  no warnings 'redefine';

  local *Succession::App::new = sub {
    my $app = $app_constructor->(@_);
    push @apps, $app;
    weaken($apps[-1]);
    return $app;
  };

  local *Succession::Model::new = sub {
    my $model = $model_constructor->(@_);
    push @models, $model;
    weaken($models[-1]);
    return $model;
  };

  my $test = Plack::Test->create(Succession->to_app);
  my $response = $test->request(GET '/info');

  ok($response->is_success, 'request completes successfully');
}

is(scalar(grep { defined } @apps), 0, 'request does not retain its App');
is(scalar(grep { defined } @models), 0, 'request does not retain its Model');

done_testing();
