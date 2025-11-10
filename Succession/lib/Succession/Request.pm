package Succession::Request;

use experimental 'signatures';

use parent 'Dancer2::Core::Request';
use DateTime;
use Succession::Model;

sub model( $self ) {
  return $self->{model} //= Succession::Model->new;
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

sub date( $self ) {
  return DateTime->today unless $self->is_date_page;
   
  $self->{date} //= do {
    my ($date_str) = $self->path =~ m[^/(\d{4}-\d\d-\d\d)];
    my ($year, $month, $day) = split /-/, $date_str;
    DateTime->new(
      year  => $year,
      month => $month,
      day   => $day,
      );
  };
    
  return $self->{date};
}

sub person( $self ) {
  return unless $self->is_person_page;

  $self->{person} //= do {
    my ($slug) = $self->path =~ m[^/p/(.*)];
    $self->model->get_person_from_slug($slug);
  };

  return $self->{person};
}

1;

