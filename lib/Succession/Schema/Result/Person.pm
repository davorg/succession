use utf8;
package Succession::Schema::Result::Person;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Succession::Schema::Result::Person

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

=head1 TABLE: C<person>

=cut

__PACKAGE__->table("person");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 name

  data_type: 'varchar'
  is_nullable: 0
  size: 50

=head2 born

  data_type: 'date'
  datetime_undef_if_invalid: 1
  is_nullable: 0

=head2 died

  data_type: 'date'
  datetime_undef_if_invalid: 1
  is_nullable: 1

=head2 parent

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 1

=head2 family_order

  data_type: 'integer'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "name",
  { data_type => "varchar", is_nullable => 0, size => 50 },
  "born",
  { data_type => "date", datetime_undef_if_invalid => 1, is_nullable => 0 },
  "died",
  { data_type => "date", datetime_undef_if_invalid => 1, is_nullable => 1 },
  "parent",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 1 },
  "family_order",
  { data_type => "integer", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 parent

Type: belongs_to

Related object: L<Succession::Schema::Result::Person>

=cut

__PACKAGE__->belongs_to(
  "parent",
  "Succession::Schema::Result::Person",
  { id => "parent" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "RESTRICT",
    on_update     => "RESTRICT",
  },
);

=head2 people

Type: has_many

Related object: L<Succession::Schema::Result::Person>

=cut

__PACKAGE__->has_many(
  "people",
  "Succession::Schema::Result::Person",
  { "foreign.parent" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 sovereigns

Type: has_many

Related object: L<Succession::Schema::Result::Sovereign>

=cut

__PACKAGE__->has_many(
  "sovereigns",
  "Succession::Schema::Result::Sovereign",
  { "foreign.person_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07045 @ 2016-12-04 17:40:32
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:6h03yIJpwjWvQGw1B+Es6Q


# You can replace this text with custom code or comments, and it will be preserved on regeneration

sub succession_on_date {
  my $self = shift;
  my ($date) = @_;

  my @desc = map {
    $_, $_->descendants_on_date($date)
  } $self->descendants_on_date($date);

  push @desc, $self->younger_siblings_and_descendants_on_date($date);

  return @desc;
}

sub younger_siblings_and_descendants_on_date {
  my $self = shift;
  my ($date) = @_;

  my $parent = $self->parent;
  return unless $self->parent;

  my @younger_siblings = $parent->descendants_on_date($date)
    -> search({
      family_order => { '>' => $self->family_order },
    });

  my @people = map {
    $_, $_->descendants_on_date($date)
  } @younger_siblings;

  return @people;
}

sub descendants_on_date {
  my $self = shift;
  my ($date) = @_;

 $date = $self->result_source->schema->storage->
         datetime_parser->format_datetime($date);

  return $self->people({
    born => { '<=' => $date },
  }, {
    order_by => 'family_order',
  });
}

__PACKAGE__->meta->make_immutable;
1;
