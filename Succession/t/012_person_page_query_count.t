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
  package Local::PersonPageQueryCounter;

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
my $counter = Local::PersonPageQueryCounter->new;

$schema->storage->debugobj($counter);
$schema->storage->debug(1);

my $test = Plack::Test->create(Succession->to_app);
my $res  = $test->request(GET '/p/83d2fc-charles-iii');

$schema->storage->debug(0);

ok($res->is_success, 'busy person page renders with a cold cache');
like($res->decoded_content, qr/Charles III/, 'rendered the expected person');

my @selects = grep { /^SELECT\b/i } @{ $counter->queries };

cmp_ok(
  scalar(@selects),
  '<=',
  4,
  'busy person page stays within its SELECT budget',
);

my @point_person_loads = grep {
  /FROM "person" "me".*WHERE.*"me"\."id" =/s
} @selects;

is(scalar(@point_person_loads), 0, 'parent and relatives are not loaded one at a time');

my @standalone_title_loads = grep {
  /FROM "title" "me"/s
} @selects;

is(scalar(@standalone_title_loads), 0, 'titles are not loaded one person at a time');

done_testing();
