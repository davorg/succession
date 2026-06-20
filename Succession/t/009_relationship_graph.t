use strict;
use warnings;

use CHI;
use Test::More;

use Succession::Model;

my $model = Succession::Model->new(
  cache => CHI->new(driver => 'Null'),
);

my $people = $model->relationship_people;
ok(keys(%$people), 'built the in-memory relationship graph');

my $person = $model->person_rs->search({
  parent => { '!=' => undef },
})->first;

BAIL_OUT('No person with a parent in the fixture database') unless $person;

my $parent_id = $person->get_column('parent');
is(
  $people->{$person->id}->parent->id,
  $parent_id,
  'wired a person to their parent in memory',
);

my $parent = $model->person_rs->find($parent_id);
my $expected = $person->sex eq 'm' ? 'Son' : 'Daughter';

is(
  $model->get_relationship_between_people($person, $parent),
  $expected,
  'calculates a relationship using the in-memory graph',
);

done_testing();
