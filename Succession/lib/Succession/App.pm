package Succession::App;

use strict;
use warnings;

use Moose;
use Moose::Util::TypeConstraints;
use Succession::Schema;
use JSON;
use DateTime;
use DateTime::Format::Strptime;

use feature 'say';

subtype 'SuccesionDate',
as 'DateTime';

coerce 'SuccesionDate',
from 'Str',
via {
  DateTime::Format::Strptime->new(pattern => '%Y-%m-%d')->parse_datetime($_);
};

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
  isa => 'SuccesionDate',
  lazy_build =>  1,
  coerce => 1,
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

sub get_succession {
  my $self = shift;

  my $succ = {
    sovereign => $self->sovereign->name,
  };

  for (@{$self->succession}) {
    push @{ $succ->{succ} }, $_->name;
  }

  return $succ;
}

sub get_succession_json {
  my $self = shift;

  my $succ = {
    sovereign => $self->sovereign->name,
  };

  my $i = 1;
  my @succ = map {{
    number => $i++,
    name   => $_->name,
    born   => $_->born->ymd,
    age    => $_->age_on_date,
  }} @{ $self->succession };

  $succ->{successors} = \@succ;

  return encode_json($succ);
}

around BUILDARGS => sub {
  my $orig  = shift;
  my $class = shift;

  if ( @_ == 1 && !ref $_[0] ) {
    return $class->$orig({ date => $_[0] });
  } else {
    return $class->$orig(@_);
  }
};

1;
