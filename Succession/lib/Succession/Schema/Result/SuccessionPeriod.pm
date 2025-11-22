use utf8;
package Succession::Schema::Result::SuccessionPeriod;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Succession::Schema::Result::SuccessionPeriod

=cut

use strict;
use warnings;

use Moose;
use MooseX::NonMoose;
use MooseX::MarkAsMethods autoclean => 1;
extends 'DBIx::Class::Core';

=head1 COMPONENTS LOADED

=over 4

=item * L<DBIx::Class::InflateColumn::DateTime>

=back

=cut

__PACKAGE__->load_components("InflateColumn::DateTime");

=head1 TABLE: C<succession_period>

=cut

__PACKAGE__->table("succession_period");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 from_date

  data_type: 'date'
  is_nullable: 0

=head2 to_date

  data_type: 'date'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "from_date",
  { data_type => "date", is_nullable => 0 },
  "to_date",
  { data_type => "date", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 succession_entries

Type: has_many

Related object: L<Succession::Schema::Result::SuccessionEntry>

=cut

__PACKAGE__->has_many(
  "succession_entries",
  "Succession::Schema::Result::SuccessionEntry",
  { "foreign.period_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07053 @ 2025-11-21 16:50:48
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:/NNZN3vgPnG/XUne277LXw

=head1 METHODS

=head2 succession_people

Given a succession_period object, returns the people in the line of succession
during that period, ordered by their rank. Takes an optional "limit" argument
to control the number of people returned.

In scalar context, returns a resultset that will return the people.

In list context, returns a list of person objects.

=cut

sub succession_people {
  my ($self, $limit) = @_;

  my %attrs = (
    order_by => 'me.rank',
  );

  $attrs{rows} = $limit if defined $limit;

  return $self->succession_entries->search_related(
    'person',
    {},
    \%attrs,
  );
}

# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
