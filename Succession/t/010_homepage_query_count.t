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
  package Local::QueryCounter;

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
}

my $schema  = Succession::Schema->get_schema;
my $counter = Local::QueryCounter->new;

$schema->storage->debugobj($counter);
$schema->storage->debug(1);

my $test = Plack::Test->create(Succession->to_app);
my $res  = $test->request(GET '/');

$schema->storage->debug(0);

ok($res->is_success, '[GET /] successful with a cold cache');

my $queries = $counter->queries;
my @selects = grep { /^SELECT\b/i } @$queries;
cmp_ok(
  scalar(@selects),
  '<=',
  6,
  'homepage stays within its SELECT budget',
);

my @point_person_loads = grep {
  /FROM "person" "me".*WHERE.*"me"\."id" =/s
} @selects;

is(
  scalar(@point_person_loads),
  0,
  'homepage does not lazily load individual people',
);

done_testing();
