package Succession::Schema::Result::SuccessionDisplayEntry;

use strict;
use warnings;
use parent 'DBIx::Class::Core';

__PACKAGE__->table('succession_display_entry');
__PACKAGE__->add_columns(
  period_id       => { data_type => 'integer', is_nullable => 0, is_foreign_key => 1 },
  display_order   => { data_type => 'integer', is_nullable => 0 },
  person_id       => { data_type => 'integer', is_nullable => 0, is_foreign_key => 1 },
  succession_rank => { data_type => 'integer', is_nullable => 1 },
);
__PACKAGE__->set_primary_key('period_id', 'display_order');
__PACKAGE__->add_unique_constraint([ 'period_id', 'person_id' ]);
__PACKAGE__->add_unique_constraint([ 'period_id', 'succession_rank' ]);
__PACKAGE__->belongs_to(period => 'Succession::Schema::Result::SuccessionPeriod', 'period_id');
__PACKAGE__->belongs_to(person => 'Succession::Schema::Result::Person', 'person_id');

1;
