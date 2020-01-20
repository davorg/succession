use utf8;
package Succession::Schema::Result::Sovereign;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Succession::Schema::Result::Sovereign

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

=head1 TABLE: C<sovereign>

=cut

__PACKAGE__->table("sovereign");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 start

  data_type: 'date'
  datetime_undef_if_invalid: 1
  is_nullable: 0

=head2 end

  data_type: 'date'
  datetime_undef_if_invalid: 1
  is_nullable: 1

=head2 person_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

=head2 image

  data_type: 'char'
  is_nullable: 1
  size: 40

=head2 image_attr

  data_type: 'varchar'
  is_nullable: 1
  size: 1000

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "start",
  { data_type => "date", datetime_undef_if_invalid => 1, is_nullable => 0 },
  "end",
  { data_type => "date", datetime_undef_if_invalid => 1, is_nullable => 1 },
  "person_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
  "image",
  { data_type => "char", is_nullable => 1, size => 40 },
  "image_attr",
  { data_type => "varchar", is_nullable => 1, size => 1000 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 person

Type: belongs_to

Related object: L<Succession::Schema::Result::Person>

=cut

__PACKAGE__->belongs_to(
  "person",
  "Succession::Schema::Result::Person",
  { id => "person_id" },
  { is_deferrable => 1, on_delete => "RESTRICT", on_update => "RESTRICT" },
);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2020-01-20 10:56:11
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:KaPzuOAqZnLBKCDUQMP38g


# You can replace this text with custom code or comments, and it will be preserved on regeneration

sub name {
  return $_[0]->person->name;
}

sub succession_on_date {
  return $_[0]->person->succession_on_date($_[1]);
}

__PACKAGE__->meta->make_immutable;
1;
