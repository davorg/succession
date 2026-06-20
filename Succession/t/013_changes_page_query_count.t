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
  package Local::ChangesPageQueryCounter;

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
my $counter = Local::ChangesPageQueryCounter->new;

$schema->storage->debugobj($counter);
$schema->storage->debug(1);

my $test = Plack::Test->create(Succession->to_app);
my $res  = $test->request(GET '/changes');

$schema->storage->debug(0);

ok($res->is_success, '/changes renders with a cold cache');
like($res->decoded_content, qr/Timeline of Changes/, 'rendered the changes timeline');

my @selects = grep { /^SELECT\b/i } @{ $counter->queries };

cmp_ok(
  scalar(@selects),
  '<=',
  3,
  '/changes stays within its SELECT budget',
);

my @lazy_change_loads = grep { /FROM "change" "me"/s } @selects;
is(scalar(@lazy_change_loads), 0, 'changes are not loaded one date at a time');

my @point_person_loads = grep {
  /FROM "person" "me".*WHERE.*"me"\."id" =/s
} @selects;
is(scalar(@point_person_loads), 0, 'changed people are not loaded one at a time');

my @standalone_title_loads = grep { /FROM "title" "me"/s } @selects;
is(scalar(@standalone_title_loads), 0, 'titles are not loaded one person at a time');

done_testing();
