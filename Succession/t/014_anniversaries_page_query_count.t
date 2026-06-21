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
  package Local::AnniversariesPageQueryCounter;

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
my $counter = Local::AnniversariesPageQueryCounter->new;

$schema->storage->debugobj($counter);
$schema->storage->debug(1);

my $test = Plack::Test->create(Succession->to_app);
my $res  = $test->request(GET '/anniversaries');

$schema->storage->debug(0);

ok($res->is_success, '/anniversaries renders with a cold cache');
like($res->decoded_content, qr/Upcoming Anniversaries and Birthdays/, 'rendered the anniversaries page');

my @selects = grep { /^SELECT\b/i } @{ $counter->queries };

cmp_ok(
  scalar(@selects),
  '<=',
  2,
  '/anniversaries stays within its SELECT budget',
);

my @point_person_loads = grep {
  /FROM "person" "me".*WHERE.*"me"\."id" =/s
} @selects;
is(scalar(@point_person_loads), 0, 'sovereigns are not loaded one person at a time');

my @standalone_title_loads = grep { /FROM "title" "me"/s } @selects;
is(scalar(@standalone_title_loads), 0, 'titles are not loaded one person at a time');

done_testing();
