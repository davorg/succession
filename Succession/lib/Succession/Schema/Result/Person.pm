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

=head2 sex

  data_type: 'enum'
  default_value: 'm'
  extra: {list => ["m","f"]}
  is_nullable: 0

=head2 wikipedia

  data_type: 'text'
  is_nullable: 1

=head2 slug

  data_type: 'varchar'
  is_nullable: 1
  size: 100

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "born",
  { data_type => "date", datetime_undef_if_invalid => 1, is_nullable => 0 },
  "died",
  { data_type => "date", datetime_undef_if_invalid => 1, is_nullable => 1 },
  "parent",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 1 },
  "family_order",
  { data_type => "integer", is_nullable => 1 },
  "sex",
  {
    data_type => "enum",
    default_value => "m",
    extra => { list => ["m", "f"] },
    is_nullable => 0,
  },
  "wikipedia",
  { data_type => "text", is_nullable => 1 },
  "slug",
  { data_type => "varchar", is_nullable => 1, size => 100 },
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
  { "foreign.person_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 children

Type: has_many

Related object: L<Succession::Schema::Result::Person>

=cut

__PACKAGE__->has_many(
  "children",
  "Succession::Schema::Result::Person",
  { "foreign.parent" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 exclusions

Type: has_many

Related object: L<Succession::Schema::Result::Exclusion>

=cut

__PACKAGE__->has_many(
  "exclusions",
  "Succession::Schema::Result::Exclusion",
  { "foreign.person_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

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

=head2 titles

Type: has_many

Related object: L<Succession::Schema::Result::Title>

=cut

__PACKAGE__->has_many(
  "titles",
  "Succession::Schema::Result::Title",
  { "foreign.person_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2019-09-20 21:54:02
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:M6t+VF+CM2kYSJIRiqkbTw


# You can replace this text with custom code or comments, and it will be preserved on regeneration

with 'MooX::Role::JSON_LD';

use DateTime;
use List::Util qw[first];
use List::MoreUtils qw[firstidx];
use Genealogy::Relationship;

sub gender { $_[0]->sex; }

has rel => (
  is => 'ro',
  isa => 'Genealogy::Relationship',
  lazy_build => 1,
);

sub _build_rel {
  my $self = shift;

  return Genealogy::Relationship->new;
}

sub json_ld_fields {
  return [
    'name',
    {
      birthDate => sub { $_[0]->born->ymd },
      deathDate => sub { defined $_[0]->died ? $_[0]->died->ymd : undef },
      url => sub { 'https://lineofsuccession.co.uk/p/' . $_[0]->slug },
    }
  ];
}

sub json_ld_type {
  return 'Person';
}

sub printlog {
  print @_ if 0;
}

sub succession_on_date {
  my $self = shift;
  my ($date) = @_;

  printlog "Getting descendants of ", $self->name, "\n";
  my @desc = map {
    $_, $_->descendants
  } $self->sorted_children;

  printlog "Got ", scalar @desc, " descendants\n";

  printlog "Adding younger siblings and their descendants\n";
  push @desc, $self->younger_siblings_and_descendants;
  printlog "Now we have ", scalar @desc, " descendants\n";

  my $ancestor = $self->parent;
  while (defined $ancestor) {
    printlog "Adding descendants of ", $ancestor->name, "\n";
    push @desc, $ancestor->younger_siblings_and_descendants;
    printlog "Now we have ", scalar @desc, " descendants\n";
    $ancestor = $ancestor->parent;
  }

  printlog $_->describe($date) . "\n" for @desc;

  printlog "Checking which of them are alive on $date\n";
  my @living_desc = grep { $_->is_alive_on_date($date) } @desc;
  printlog "Now we have ", scalar @living_desc, " descendants\n";

  return @living_desc;
}

sub younger_siblings_and_descendants {
  my $self = shift;
  my ($date) = @_;

  my $parent = $self->parent;
  return unless $self->parent;

  my @younger_siblings = $parent->sorted_children->search({
    family_order => { '>' => $self->family_order },
  }, { prefetch => [ 'titles', 'exclusions' ]});

  my @people = map {
    $_, $_->descendants,
  } @younger_siblings;

  return @people;
}

sub descendants {
  my $self = shift;
  my ($date) = @_;

  my @desc = $self->sorted_children->search({}, {
    prefetch => [ 'titles', 'exclusions'],
  });

  return map { $_, $_->descendants } @desc;
}

sub is_alive_on_date {
  my $self = shift;
  my ($date) = @_;

  return 0 if $self->born > $date;
  return 1 if !defined $self->died;
  return 0 if $self->died < $date;
  return 1;
}

sub sorted_children {
  my $self = shift;

  return $self->children({}, {
    order_by => 'family_order',
  });
}

sub describe {
  my $self = shift;
  my ($date) = @_;

  my $fmt = '%d %B %Y';

  my $desc = $self->name_on_date($date) .
    ' (born ' . $self->born->strftime($fmt);
  if (defined $self->is_alive_on_date($date)) {
    $desc .= ', age ' . $self->age_on_date($date);
  } else {
    $desc .= ', died ' . $self->died->strftime($fmt);
  }
  $desc .= ')';

  return $desc;
}

sub age_on_date {
  my $self = shift;
  my ($date) = @_;

  $date //= DateTime->now;

  my $age = $date - $self->born;
  return $age->years;
}

sub name {
  my $self = shift;

  if (my $title = $self->titles({ is_default => 1})->first) {
    return $title->title;
  } else {
    return 'XXX';
  }
}

sub name_on_date {
  my $self = shift;
  my ($date) = @_;

  unless ($self->is_alive_on_date($date)) {
    return '[' . $self->name . ']';
  }

  my $dtf      = $self->result_source->storage->datetime_parser;
  my $fmt_date = $dtf->format_datetime($date);

  my $name = $self->titles([{
    start => undef,
    end   => undef,
  },{
    start => undef,
    end   => { '>'  => $fmt_date },
  },{
    start => { '<=' => $fmt_date },
    end   => undef,
  },{
    start => { '<=' => $fmt_date },
    end   => { '>'  => $fmt_date },
  }])->first;

  if ($name) {
    return $name->title;
  } else {
    return $self->name;
  }
}

sub excluded_on_date {
  my $self = shift;
  my ($date) = @_;

  my $dtf      = $self->result_source->storage->datetime_parser;
  my $fmt_date = $dtf->format_datetime($date);

  my $exc = $self->exclusions([{
    start => undef,
    end   => undef,
  },{
    start => undef,
    end   => { '>'  => $fmt_date },
  },{
    start => { '<=' => $fmt_date },
    end   => undef,
  },{
    start => { '<=' => $fmt_date },
    end   => { '>'  => $fmt_date },
  }])->first;

  return unless $exc;
  return $exc->reason;
}

sub ancestors {
  my $self = shift;

  return $self->rel->get_ancestors($self);
}

sub most_recent_common_ancestor_with {
  my $self = shift;
  my ($person) = @_;

  return $self->rel->most_recent_common_ancestor($self, $person);
}

sub relationship_with {
  my $self = shift;
  my ($person) = @_;

  return $self->rel->get_relationship($self, $person);
}

sub anc_string {
  my $self = shift;

  return join ' / ', map { $_->name } $self->ancestors;
}

__PACKAGE__->meta->make_immutable;
1;
