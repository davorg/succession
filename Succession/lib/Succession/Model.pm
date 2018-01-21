package Succession::Model;

use strict;
use warnings;

use Moose;
use DateTime;
use Succession::Schema;

has schema => (
  is => 'ro',
  lazy_build => 1,
  isa => 'Succession::Schema',
);

sub _build_schema {
  return Succession::Schema->get_schema;
}

has sovereign_rs => (
  is => 'ro',
  isa => 'DBIx::Class::ResultSet',
  lazy_build =>  1,
  handles => [ qw(sovereign_on_date) ],
);

sub _build_sovereign_rs {
  return $_[0]->schema->resultset('Sovereign');
}

has change_date_rs => (
  is => 'ro',
  isa => 'DBIx::Class::ResultSet',
  lazy_build =>  1,
);

sub _build_change_date_rs {
  return $_[0]->schema->resultset('ChangeDate');
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

sub get_canonical_date {
  my $self = shift;
  my ($date) = @_;

  my $max_date = $self->change_date_rs->get_column('change_date')->max;

  my $search_date =
    $self->schema->storage->datetime_parser->format_datetime($date);

  my ($canon_date) = $self->change_date_rs->search({
    change_date => { '<=', $search_date },
  },{
    order_by => { -desc => 'change_date' },
  });

  # TODO: Remove hack!
  return '' unless $canon_date;

  if ($canon_date->change_date->strftime('%Y-%m-%d') eq $max_date) {
    return '';
  } else {
    return $canon_date->change_date->strftime('%Y-%m-%d');
  }
}

1;
