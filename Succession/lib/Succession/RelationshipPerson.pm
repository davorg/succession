package Succession::RelationshipPerson;

use v5.32;
use Moo;

has id => (
  is => 'ro',
  required => 1,
);

has gender => (
  is => 'ro',
  required => 1,
);

has parent => (
  is => 'rw',
);

1;
