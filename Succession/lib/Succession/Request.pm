package Succession::Request;

use Moose;
extends 'Dancer2::Core::Request';
use experimental 'signatures'; # After Moose because Moose turns all warnings on

use DateTime;
use Succession::Model;

has model => (
  is => 'ro',
  isa => 'Succession::Model',
  lazy => 1,
  builder => '_build_model',
);

sub _build_model( $ ) {
  return Succession::Model->new;
}

has date => (
  is => 'ro',
  lazy => 1,
  builder => '_build_date',
);

sub _build_date( $self ) {
  return DateTime->today unless $self->is_date_page;

  my ($date_str) = $self->path =~ m[^/(\d{4}-\d\d-\d\d)];
  my ($year, $month, $day) = split /-/, $date_str;

  return DateTime->new(
    year  => $year,
    month => $month,
    day   => $day,
    );
}

sub is_date_page( $self ) {
  return $self->path =~ m[^/\d\d\d\d-\d\d-\d\d];
}

sub is_home_page( $self ) {
  return $self->path eq '/';
}

sub is_person_page( $self ) {
  return $self->path =~ m[^/p/];
}

has person => (
  is => 'ro',
  isa => 'Maybe[Succession::Schema::Result::Person]',
  lazy => 1,
  builder => '_build_person',
);

sub _build_person( $self ) {
  return unless $self->is_person_page;

  my ($slug) = $self->path =~ m[^/p/(.*)];
  return $self->model->get_person_from_slug($slug);
}

1;

