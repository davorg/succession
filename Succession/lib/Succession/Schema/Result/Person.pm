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
  is_nullable: 0

=head2 died

  data_type: 'date'
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
  is_nullable: 0

=head2 wikipedia

  data_type: 'text'
  is_nullable: 1

=head2 slug

  data_type: 'varchar'
  is_nullable: 1
  size: 100

=head2 wikidata_qid

  data_type: 'varchar'
  is_nullable: 1
  size: 32

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "born",
  { data_type => "date", is_nullable => 0 },
  "died",
  { data_type => "date", is_nullable => 1 },
  "parent",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 1 },
  "family_order",
  { data_type => "integer", is_nullable => 1 },
  "sex",
  { data_type => "enum", default_value => "m", is_nullable => 0 },
  "wikipedia",
  { data_type => "text", is_nullable => 1 },
  "slug",
  { data_type => "varchar", is_nullable => 1, size => 100 },
  "wikidata_qid",
  { data_type => "varchar", is_nullable => 1, size => 32 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 UNIQUE CONSTRAINTS

=head2 C<wikidata_qid_unique>

=over 4

=item * L</wikidata_qid>

=back

=cut

__PACKAGE__->add_unique_constraint("wikidata_qid_unique", ["wikidata_qid"]);

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
    is_deferrable => 0,
    join_type     => "LEFT",
    on_delete     => "RESTRICT",
    on_update     => "RESTRICT",
  },
);

=head2 positions

Type: has_many

Related object: L<Succession::Schema::Result::Position>

=cut

__PACKAGE__->has_many(
  "positions",
  "Succession::Schema::Result::Position",
  { "foreign.person_id" => "self.id" },
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

=head2 succession_entries

Type: has_many

Related object: L<Succession::Schema::Result::SuccessionEntry>

=cut

__PACKAGE__->has_many(
  "succession_entries",
  "Succession::Schema::Result::SuccessionEntry",
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


# Created by DBIx::Class::Schema::Loader v0.07053 @ 2025-11-21 16:50:48
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:4ODsQvzyp2p45/g5YZJDAg


# You can replace this text with custom code or comments, and it will be preserved on regeneration

use feature 'state';
use experimental 'signatures';

with 'MooX::Role::JSON_LD';

use DateTime;
use List::Util qw[first];
use List::MoreUtils qw[firstidx];
use Genealogy::Relationship;
use Digest::SHA;
use Text::Unidecode;
use URI::Escape qw(uri_escape_utf8);

use Succession::WikiData::Entity;

sub gender( $self ) { return $self->sex; }

has rel => (
  is => 'ro',
  isa => 'Genealogy::Relationship',
  lazy_build => 1,
);

sub _build_rel($) {
  return Genealogy::Relationship->new;
}

sub json_ld_fields($) {
  return [
    'name',
    {
      birthDate => sub { $_[0]->born->ymd },
      deathDate => sub { defined $_[0]->died ? $_[0]->died->ymd : undef },
      url => sub { 'https://lineofsuccession.co.uk/p/' . $_[0]->slug },
    }
  ];
}

sub json_ld_type($) {
  return 'Person';
}

sub printlog(@args) {
  print @args if 0;
}

sub succession_on_date( $self, $date ) {
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

sub siblings( $self ) {
  return unless $self->parent;

  return $self->parent->sorted_children->search({
    id => { '!=' => $self->id },
  });
}

sub younger_siblings_and_descendants( $self ) {
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

sub descendants( $self) {
  my @desc = $self->sorted_children->search({}, {
    prefetch => [ 'titles', 'exclusions'],
  });

  return map { $_, $_->descendants } @desc;
}

sub is_alive_on_date( $self, $date = undef) {
  $date ||= DateTime->now;

  return 0 if $self->born > $date;
  return 1 if !defined $self->died;
  return 0 if $self->died < $date;
  return 1;
}

sub sorted_children(  $self ) {
  return $self->children({}, {
    order_by => 'family_order',
  });
}

sub describe( $self, $date ) {
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

sub age_on_date( $self, $date ) {
  $date //= DateTime->now;

  my $age = $date - $self->born;
  return $age->years || ($age->months . ' months');
}

sub name( $self ) {
  if (my $title = $self->titles({ is_default => 1})->first) {
    return $title->title;
  } else {
    return 'XXX';
  }
}

sub name_on_date( $self, $date ) {
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

sub excluded_on_date( $self, $date ) {
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

sub ancestors(  $self ) {
  return $self->rel->get_ancestors($self);
}

sub most_recent_common_ancestor_with( $self, $person ) {
  return $self->rel->most_recent_common_ancestor($self, $person);
}

sub relationship_with( $self, $person ) {
  return $self->rel->get_relationship($self, $person);
}

sub anc_string( $self ) {
  return join ' / ', map { $_->name } $self->ancestors;
}

sub position_obj_on_date( $self, $date ) {
  return 0 if $self->is_sovereign_on_date($date);

  my $dtf      = $self->result_source->storage->datetime_parser;
  my $fmt_date = $dtf->format_datetime($date);

  my $pos = $self->positions([{
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

  return $pos;
}

sub position_on_date(  $self, $date ) {
  my $pos = $self->position_obj_on_date($date);

  return unless $pos;
  return $pos->position;
}

sub years( $self ) {
  my $years = $self->born->year . ' - ';
  $years .= $self->died->year if $self->died;

  return $years;
}

sub make_slug( $self ) {
  my $sha = Digest::SHA->new;

  # Use only immutable fields for the hex part
  $sha->add($self->id);
  $sha->add($self->sex);
  $sha->add($self->born);
  my $hex = substr($sha->hexdigest, 0, 6);

  # Use the current name for the variable part
  my $slugname = lc unidecode($self->name =~ s/\W+/-/gr);
  my $slug = $hex . '-' . $slugname;

  warn $self->name, " / $slug\n";

  $self->update({ slug => $slug });
}

sub regenerate_slug( $self ) {
  # Extract the hex part from the current slug
  my $current_slug = $self->slug;
  return unless $current_slug;

  my ($hex) = $current_slug =~ /^([0-9a-f]{6})-/;
  return unless $hex;

  # Generate new slug with the same hex but current name
  my $slugname = lc unidecode($self->name =~ s/\W+/-/gr);
  my $slug = $hex . '-' . $slugname;

  warn $self->name, " / regenerated slug: $slug\n";

  $self->update({ slug => $slug });
}

sub is_sovereign_on_date(  $self, $date ) {
  my $sch = $self->result_source->schema;

  my $sov = $sch->resultset('Sovereign')->sovereign_on_date($date);

  return $sov->person->id == $self->id;
}

sub add_child(  $self, $args ) {
  unless (exists $args->{died}) {
    $args->{died} = undef;
  }

  my @missing;

  for (qw[born sex name]) {
    push @missing, $_ unless length $args->{$_}
  }

  die 'Missing fields for child creation - ' . join(', ', @missing) . "\n"
    if @missing;

  my $child_data = {
    born => $args->{born},
    died => $args->{died},
    sex  => $args->{sex},
  };

  for (qw[wikipedia wikidata_qid]) {
    $child_data->{$_} = $args->{$_} if exists $args->{$_};
  }

  my $child = $self->add_to_children($child_data);

  if ($child) {
    $child->add_to_titles({
      title       => $args->{name},
      is_default => 1,
    });

    $child->make_slug;
  }

  $self->reorder_family;

  return $child;
}

sub reorder_family( $self ) {
  my $schema = $self->result_source->schema;

  # Primogeniture cut-off (UK rule change)
  my $cutoff = '2011-10-28';

  # We do the whole reorder in one transaction for atomicity
  $schema->txn_do(sub {
    # Order:
    #  (sex='m' AND born < cutoff) DESC  -> priority group (1) first
    #  born IS NULL ASC                  -> known birthdates before NULLS
    #  born ASC                          -> older first
    #  id ASC                            -> stable tie-break
    my $children_rs = $self->children->search(
      {},
      {
        order_by => \[
          q{ (sex = 'm' AND born < ?) DESC, born IS NULL, born ASC, id ASC },
          $cutoff
        ],
      }
    );

    my $i = 0;
    while (my $child = $children_rs->next) {
      $child->update({ family_order => ++$i });
    }
  });

  return $self;
}

sub wikidata( $self ) {
  my $qid  = $self->wikidata_qid or return;

  state $cache;

  return $cache->{$qid} //= Succession::WikiData::Entity->new(qid => $qid);
}

sub image_url( $self, $width = 400 ) {
  my $wd = $self->wikidata or return;
  my $filename = $wd->image_filename or return;
  my $enc_filename = uri_escape_utf8($filename);

  return 'https://commons.wikimedia.org/wiki/Special:FilePath/' .
         "$enc_filename?width=$width";
}

sub short_bio( $self, $length = 360 ) {
  my $wd = $self->wikidata or return;
  my $ent = $wd->entity || {};

  my $bio = $ent->{descriptions}{'en-gb'}{value}
          || $ent->{descriptions}{'en'}{value}
          || '';

  return _trim(ucfirst $bio);
}

sub _trim( $s, $max = 360 ) {
  return $s unless defined $s && $max && length($s) > $max;
  $s =~ s/\s+/ /g;
  my $cut = substr($s, 0, $max);
  $cut =~ s/\s+\S*$//;       # avoid chopping mid-word
  return "$cut…";
}

__PACKAGE__->meta->make_immutable;
1;
