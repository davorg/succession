use strict;
use warnings;

BEGIN {
  $ENV{SUCC_CACHE_DRIVER} = 'Null';
}

use HTTP::Request::Common;
use Plack::Test;
use Test::More;

use Succession;
use Succession::Schema;

{
  package Local::StaticPageQueryCounter;

  use parent 'DBIx::Class::Storage::Statistics';

  sub query_start {
    my ($self, $sql) = @_;
    push @{ $self->{queries} }, $sql;
  }

  sub query_end { }

  sub queries {
    my ($self) = @_;
    return $self->{queries} // [];
  }

  sub reset {
    my ($self) = @_;
    $self->{queries} = [];
  }
}

my $schema  = Succession::Schema->get_schema;
my $counter = Local::StaticPageQueryCounter->new;
my $test    = Plack::Test->create(Succession->to_app);

$schema->storage->debugobj($counter);

for my $case (
  [ '/dates', 'dates page' ],
  [ '/lp', 'letters patent page' ],
  [ '/r/how-many-people-are-in-the-line-of-succession', 'reference page' ],
) {
  my ($path, $name) = @$case;
  $counter->reset;
  $schema->storage->debug(1);

  my $res = $test->request(GET $path);

  $schema->storage->debug(0);

  ok($res->is_success, "$name renders");

  my @selects = grep { /^SELECT\b/i } @{ $counter->queries };
  is(scalar(@selects), 0, "$name does not query the database");
  unlike($res->decoded_content, qr{application/ld\+json}, "$name omits succession JSON-LD");
}

my $api_res = $test->request(GET '/api?date=1952-02-06&count=30');
is($api_res->code, 404, 'experimental API route is disabled');

done_testing();
