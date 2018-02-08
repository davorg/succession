package Succession::App;

use strict;
use warnings;

use Moose;
use Moose::Util::TypeConstraints;
use JSON;
use DateTime;
use DateTime::Format::Strptime;
use Lingua::EN::Numbers 'num2en';

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
  handles => [ qw(get_succession get_succession_json interesting_dates ) ],
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
  return DateTime->today;
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
  )->parse_datetime('1901-01-22') },
);

has list_size => (
  is => 'ro',
  isa => 'Int',
  required => 1,
  default => 30,
);

has list_size_str => (
  is => 'ro',
  isa => 'Str',
  required => 1,
  lazy_build => 1,
);

sub _build_list_size_str {
  my $self = shift;
  return num2en($self->list_size);
}

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
  return $self->model->succession_on_date($self->date);
}

around BUILDARGS => sub {
  my $orig  = shift;
  my $class = shift;

  if ( @_ == 1 && !ref $_[0] ) {
    return $class->$orig({ date => $_[0] });
  } elsif (!@_ or (@_ == 1 and !defined $_[0])) {
    return $class->$orig({ date => DateTime->today });
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

sub is_valid_date {
  my $self = shift;

  return !! DateTime::Format::Strptime->new(
    pattern => '%Y-%m-%d'
  )->parse_datetime($_[0]);
}

sub canonical_date {
  return $_[0]->model->get_canonical_date($_[0]->date);
}

sub page_date {
  my $self = shift;

  return '' unless $self->date;
  return '' if $self->date == $self->today;
  return $self->date->strftime('%Y-%m-%d');
}

sub prev_change_date {
  my $self = shift;
  my $date = $self->model->get_prev_change_date($self->date);
  return $date ? $date->change_date : '';
}

sub next_change_date {
  my $self = shift;
  my $date = $self->model->get_next_change_date($self->date);
  return $date ? $date->change_date : '';
}

sub get_changes {
  my $self = shift;
  return $self->model->get_changes_on_date($self->date);
}

1;
