use utf8;
package Succession::Schema::Result::ChangeDate;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Succession::Schema::Result::ChangeDate

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

=head1 TABLE: C<change_date>

=cut

__PACKAGE__->table("change_date");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 change_date

  data_type: 'date'
  datetime_undef_if_invalid: 1
  is_nullable: 1

=head2 succession

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "change_date",
  { data_type => "date", datetime_undef_if_invalid => 1, is_nullable => 1 },
  "succession",
  { data_type => "varchar", is_nullable => 1, size => 255 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 changes

Type: has_many

Related object: L<Succession::Schema::Result::Change>

=cut

__PACKAGE__->has_many(
  "changes",
  "Succession::Schema::Result::Change",
  { "foreign.change_date_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2019-09-20 21:54:02
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:cCx2uc9BysKWDtqq7mucwA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
