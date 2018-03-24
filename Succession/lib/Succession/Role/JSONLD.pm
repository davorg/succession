package Succession::Role::JSONLD;

use Moose::Role;
use JSON;
use Carp;

requires qw[json_ld_type json_ld_fields];

has json => (
  isa => 'JSON',
  is  => 'ro',
  lazy_build => 1,
);

sub _build_json {
  return JSON->new->utf8->space_after->indent->pretty;
}

sub json_ld_data {
  my $self = shift;

  my $data = {
    '@context' => 'http://schema.org',
    '@type'    => $self->json_ld_type,
  };

  foreach (@{$self->json_ld_fields}) {
    if (my $reftype = ref $_) {
      if ($reftype eq 'HASH') {
	while (my ($key, $val) = each %{$_}) {
          if (ref $val eq 'CODE') {
            $data->{$key} = $val->($self);
	  } else {
            $data->{$key} = $self->$val;
          }
	}
      } else {
        carp "Weird JSON-LD reference: $reftype";
	next;
      }
    } else {
      $data->{$_} = $self->$_;
    } 
  }

  return $data;
}

sub json_ld {
  my $self = shift;

  return $self->json->encode($self->json_ld_data);
}

1;
