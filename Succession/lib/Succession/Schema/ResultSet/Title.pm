package Succession::Schema::ResultSet::Title;

use strict;
use warnings;
use experimental 'signatures';

use parent 'DBIx::Class::ResultSet';

sub order_by_date( $self ) {
  return $self->search(undef, { order_by => 'start' });
}

1;
