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
  package Local::DatePageQueryCounter;

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
my $counter = Local::DatePageQueryCounter->new;

$schema->storage->debugobj($counter);
$schema->storage->debug(1);

my $test = Plack::Test->create(Succession->to_app);
my $res  = $test->request(GET '/1952-02-06');

$schema->storage->debug(0);

ok($res->is_success, 'dated succession page renders with a cold cache');

my @selects = grep { /^SELECT\b/i } @{ $counter->queries };

cmp_ok(
  scalar(@selects),
  '<=',
  8,
  'dated succession page stays within its SELECT budget',
);

my @canonical_lookups = grep {
  /FROM "change_date" "me".*WHERE.*"change_date" <=/s
} @selects;
is(scalar(@canonical_lookups), 1, 'canonical change date is looked up once');

my @max_change_date_lookups = grep {
  /SELECT MAX\(.*"change_date"/s
} @selects;
is(scalar(@max_change_date_lookups), 1, 'maximum change date is looked up once');

done_testing();
