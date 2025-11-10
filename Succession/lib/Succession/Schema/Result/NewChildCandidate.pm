use utf8;
package Succession::Schema::Result::NewChildCandidate;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Succession::Schema::Result::NewChildCandidate

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

=head1 TABLE: C<new_child_candidate>

=cut

__PACKAGE__->table("new_child_candidate");

=head1 ACCESSORS

=head2 parent_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

=head2 child_label

  data_type: 'varchar'
  is_nullable: 0
  size: 255

=head2 child_dob

  data_type: 'date'
  datetime_undef_if_invalid: 1
  is_nullable: 1

=head2 child_qid

  data_type: 'varchar'
  is_nullable: 0
  size: 32

=head2 source_url

  data_type: 'varchar'
  is_nullable: 1
  size: 512

=head2 first_seen

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  default_value: 'current_timestamp()'
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "parent_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
  "child_label",
  { data_type => "varchar", is_nullable => 0, size => 255 },
  "child_dob",
  { data_type => "date", datetime_undef_if_invalid => 1, is_nullable => 1 },
  "child_qid",
  { data_type => "varchar", is_nullable => 0, size => 32 },
  "source_url",
  { data_type => "varchar", is_nullable => 1, size => 512 },
  "first_seen",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    default_value => "current_timestamp()",
    is_nullable => 0,
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</parent_id>

=item * L</child_qid>

=back

=cut

__PACKAGE__->set_primary_key("parent_id", "child_qid");

=head1 RELATIONS

=head2 parent

Type: belongs_to

Related object: L<Succession::Schema::Result::Person>

=cut

__PACKAGE__->belongs_to(
  "parent",
  "Succession::Schema::Result::Person",
  { id => "parent_id" },
  { is_deferrable => 1, on_delete => "RESTRICT", on_update => "RESTRICT" },
);


# Created by DBIx::Class::Schema::Loader v0.07053 @ 2025-09-25 12:08:08
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:Ko7vFsKY6OxsXoxc0Yasqg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
