package Succession::Schema::ResultSet::SuccessionEntry;

use strict;
use warnings;
use experimental 'signatures';

use parent 'DBIx::Class::ResultSet';

sub order_by_date($self) {
  return $self->search(
    {},
    {
      join     => 'period',
      order_by => 'period.from_date',
      prefetch => 'period',
    }
  );
}

1;
