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
  is_nullable: 0
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
  { data_type => "varchar", is_nullable => 0, size => 100 },
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


# Created by DBIx::Class::Schema::Loader v0.07047 @ 2018-01-22 19:20:57
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:abM6MUxFzxm15QSRQAM45Q


# You can replace this text with custom code or comments, and it will be preserved on regeneration

use DateTime;
use List::Util qw[first];
use List::MoreUtils qw[firstidx];

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
  });

  my @people = map {
    $_, $_->descendants
  } @younger_siblings;

  return @people;
}

sub descendants {
  my $self = shift;
  my ($date) = @_;

  my @desc = $self->sorted_children;

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

  return $self->people({}, {
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
    end   => { '>=' => $fmt_date },
  },{
    start => { '<=' => $fmt_date },
    end   => undef,
  },{
    start => { '<=' => $fmt_date },
    end   => { '>=' => $fmt_date },
  }])->first;

  if ($name) {
    return $name->title;
  } else {
    return $self->name;
  }
}

sub ancestors {
  my $self = shift;

  if ($self->parent) {
    return ($self, $self->parent->ancestors);
  } else {
    return $self;
  }
}

sub most_recent_common_ancestor_with {
  my $self = shift;
  my ($person) = @_;

  my @my_ancestors = $self->ancestors;

  if (my $anc = first { $_->id == $person->id } @my_ancestors) {
    return $anc;
  }

  my @their_ancestors = $person->ancestors;

  if (my $anc = first { $_->id == $self->id } @their_ancestors) {
    return $anc;
  }

  for my $my_anc (@my_ancestors) {
    for my $their_anc (@their_ancestors) {
      return $my_anc if $my_anc->id == $their_anc->id;
    }
  }

  die "Can't find a common ancestor.\n";
}

sub relationship_with {
  my $self = shift;
  my ($person) = @_;

  our $relationships = {
    m => [
    [ undef, 'Father', 'Grandfather', 'Great grandfather', 'Great, great grandfather' ],
    ['Son', 'Brother', 'Uncle', 'Great uncle', 'Great, great uncle' ],
    ['Grandson', 'Nephew', 'First cousin', 'First cousin once removed', 'First cousin twice removed' ],
    ['Great grandson', 'Great nephew', 'First cousin once removed', 'Second cousin', 'Second cousin once removed'],
    ['Great, great grandson', 'Great, great nephew', 'First cousin twice removed', 'Second cousin once removed', 'Third cousin',],
    ],
    f => [
    [ undef, 'Mother', 'Grandmother', 'Great grandmother', 'Great, great grandmother' ],
    ['Daughter', 'Sister', 'Aunt', 'Great aunt', 'Great, great aunt' ],
    ['Granddaughter', 'Niece', 'First cousin', 'First cousin once removed', 'First cousin twice removed'],
    ['Great granddaughter', 'Great niece', 'First cousin once removed', 'Second cousin', 'Second cousin once removed'],
    ['Great, great granddaughter', 'Great, great niece', 'First cousin twice removed', 'Second cousin once removed', 'Third cousin',],
    ],
  };

  my ($x, $y) = $self->get_relationship_coords($person);

  return $relationships->{$self->sex}[$x][$y] // join '/', ($x, $y);
}

sub get_relationship_coords {
  my $self = shift;
  my ($person) = @_;

  my @my_ancestors = $self->ancestors;

  my $idx = firstidx { $_->id == $person->id } @my_ancestors;
  return ($idx, 0) if $idx != -1;

  my @their_ancestors = $person->ancestors;

  $idx = firstidx { $_->id == $self->id } @their_ancestors;
  return (0, $idx) if $idx != -1;

  for my $i (0 .. $#my_ancestors) {
    for my $j (0 .. $#their_ancestors) {
      return ($i, $j) if $my_ancestors[$i]->id == $their_ancestors[$j]->id;
    }
  }

  die "Can't work out the relationship.\n";
}

sub anc_string {
  my $self = shift;

  return join ' / ', map { $_->name } $self->ancestors;
}

__PACKAGE__->meta->make_immutable;
1;
