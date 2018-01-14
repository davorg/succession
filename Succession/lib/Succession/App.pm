package Succession::App;

use strict;
use warnings;

use Moose;
use Moose::Util::TypeConstraints;
use JSON;
use DateTime;
use DateTime::Format::Strptime;

use Succession::Model;

use feature 'say';

subtype 'SuccessionDate',
as 'DateTime';

coerce 'SuccessionDate',
from 'Str',
via {
  DateTime::Format::Strptime->new(pattern => '%Y-%m-%d')->parse_datetime($_);
};

has model => (
  is => 'ro',
  isa => 'Succession::Model',
  lazy_build => 1,
  handles => [ qw(get_succession get_succession_json) ],
);

sub _build_model {
  return Succession::Model->new;
}

has date => (
  is => 'ro',
  isa => 'SuccessionDate',
  lazy_build =>  1,
  coerce => 1,
);

sub _build_date {
  return DateTime->now;
}

has today => (
  is => 'ro',
  isa => 'SuccessionDate',
  lazy_build => 1,
  coerce => 1,
);

sub _build_today {
  return DateTime->today;
}

has earliest => (
  is => 'ro',
  isa => 'DateTime',
  required => 1,
  default => sub { DateTime::Format::Strptime->new(
    pattern => '%Y-%m-%d'
  )->parse_datetime('1910-05-06') },
);

has sovereign => (
  is => 'ro',
  isa => 'Succession::Schema::Result::Sovereign',
  lazy_build => 1,
);

sub _build_sovereign {
  my $self = shift;
  return $self->model->sovereign_on_date($self->date);
}

has succession => (
  is => 'ro',
  isa => 'ArrayRef',
  lazy_build => 1,
);

sub _build_succession {
  my $self = shift;
  return [ $self->sovereign->succession_on_date($self->date) ];
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

sub too_early {
  my $self = shift;
  return $self->date < $self->earliest;
}

sub too_late {
  my $self = shift;
  return DateTime->now < $self->date;
}

1;
