package Succession::App;

use strict;
use warnings;

use Moose;

use Succession::Schema;
use JSON;
use DateTime;
use DateTime::Format::Strptime;

has schema => (
  is => 'ro',
  isa => 'Succession::Schema',
  lazy_build =>  1,
);

sub _build_schema {
  return Succession::Schema->get_schema;
}

has sovereign_rs => (
  is => 'ro',
  isa => 'DBIx::Class::ResultSet',
  lazy_build =>  1,
);

sub _build_sovereign_rs {
  return $_[0]->schema->resultset('Sovereign');
}

has date => (
  is => 'ro',
  isa => 'Maybe[DateTime]',
  lazy_build =>  1,
#  coerce => 1,
);

sub _build_date {
  return DateTime->now;
}

has sovereign => (
  is => 'ro',
  isa => 'Succession::Schema::Result::Sovereign',
  lazy_build =>  1,
);

sub _build_sovereign {
  my $self = shift;

  return $self->sovereign_rs->sovereign_on_date($self->date);
}

has succession => (
  is => 'ro',
  isa => 'ArrayRef',
  lazy_build =>  1,
);

sub _build_succession {
  my $self = shift;

  return [ $self->sovereign->succession_on_date($self->date) ];
}

1;
