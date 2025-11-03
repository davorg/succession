package Succession::Schema::ResultSet::Exclusion;

use strict;
use warnings;

use parent 'DBIx::Class::ResultSet';

sub order_by_date {
  my $self = shift;

  return $self->search(undef, { order_by => 'start' });
}

1;
