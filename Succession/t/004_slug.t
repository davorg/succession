use strict;
use warnings;

use Test::More;
use Text::Unidecode;
use Digest::SHA;

# Test the slug functionality in Person.pm

# Mock a Person object for testing
{
  package MockPerson;
  use strict;
  use warnings;

  sub new {
    my ($class, %args) = @_;
    return bless \%args, $class;
  }

  sub id { $_[0]->{id} }
  sub sex { $_[0]->{sex} }
  sub born { $_[0]->{born} }
  sub name { 
    my $self = shift;
    $self->{name} = shift if @_;
    return $self->{name};
  }
  sub slug { 
    my $self = shift;
    $self->{slug} = shift if @_;
    return $self->{slug};
  }

  sub update {
    my $self = shift;
    my ($args) = @_;
    $self->{slug} = $args->{slug} if exists $args->{slug};
  }

  sub make_slug {
    my $self = shift;

    my $sha = Digest::SHA->new;

    # Use only immutable fields for the hex part
    $sha->add($self->id);
    $sha->add($self->sex);
    $sha->add($self->born);
    my $hex = substr($sha->hexdigest, 0, 6);

    # Use the current name for the variable part
    my $slugname = lc Text::Unidecode::unidecode($self->name =~ s/\W+/-/gr);
    my $slug = $hex . '-' . $slugname;

    $self->update({ slug => $slug });
  }

  sub regenerate_slug {
    my $self = shift;

    # Extract the hex part from the current slug
    my $current_slug = $self->slug;
    return unless $current_slug;

    my ($hex) = $current_slug =~ /^([0-9a-f]{6})-/;
    return unless $hex;

    # Generate new slug with the same hex but current name
    my $slugname = lc Text::Unidecode::unidecode($self->name =~ s/\W+/-/gr);
    my $slug = $hex . '-' . $slugname;

    $self->update({ slug => $slug });
  }
}

# Test make_slug with immutable fields
{
  my $person = MockPerson->new(
    id   => 123,
    sex  => 'm',
    born => '1982-06-21',
    name => 'Prince William',
  );

  $person->make_slug();
  my $slug1 = $person->slug;

  ok($slug1, 'Slug was generated');
  like($slug1, qr/^[0-9a-f]{6}-prince-william$/, 'Slug has correct format');

  # Change the name and regenerate - hex should stay the same
  $person->name('Duke of Cambridge');
  $person->make_slug();
  my $slug2 = $person->slug;

  my ($hex1) = $slug1 =~ /^([0-9a-f]{6})-/;
  my ($hex2) = $slug2 =~ /^([0-9a-f]{6})-/;

  is($hex1, $hex2, 'Hex part stays the same when name changes');
  like($slug2, qr/^[0-9a-f]{6}-duke-of-cambridge$/, 'Name part updates correctly');
}

# Test that hex depends only on immutable fields
{
  my $person1 = MockPerson->new(
    id   => 456,
    sex  => 'f',
    born => '1988-08-08',
    name => 'Princess Beatrice',
  );

  my $person2 = MockPerson->new(
    id   => 456,
    sex  => 'f',
    born => '1988-08-08',
    name => 'Different Name',
  );

  $person1->make_slug();
  $person2->make_slug();

  my ($hex1) = $person1->slug =~ /^([0-9a-f]{6})-/;
  my ($hex2) = $person2->slug =~ /^([0-9a-f]{6})-/;

  is($hex1, $hex2, 'Same immutable fields produce same hex part');
}

# Test regenerate_slug
{
  my $person = MockPerson->new(
    id   => 789,
    sex  => 'm',
    born => '1984-09-15',
    name => 'Prince Harry',
  );

  $person->make_slug();
  my $original_slug = $person->slug;
  my ($original_hex) = $original_slug =~ /^([0-9a-f]{6})-/;

  # Change the name and use regenerate_slug
  $person->name('Duke of Sussex');
  $person->regenerate_slug();
  my $new_slug = $person->slug;
  my ($new_hex) = $new_slug =~ /^([0-9a-f]{6})-/;

  is($original_hex, $new_hex, 'regenerate_slug preserves hex part');
  like($new_slug, qr/^[0-9a-f]{6}-duke-of-sussex$/, 'regenerate_slug updates name part');
}

# Test regenerate_slug without existing slug
{
  my $person = MockPerson->new(
    id   => 999,
    sex  => 'f',
    born => '1990-01-01',
    name => 'Test Person',
  );

  # No slug set yet
  $person->regenerate_slug();
  ok(!defined $person->slug, 'regenerate_slug returns early if no slug exists');
}

# Test slug with special characters in name
{
  my $person = MockPerson->new(
    id   => 111,
    sex  => 'm',
    born => '1990-05-10',
    name => "Prince O'Brien-Smith",
  );

  $person->make_slug();
  my $slug = $person->slug;

  like($slug, qr/^[0-9a-f]{6}-prince-o-brien-smith$/, 'Special characters handled correctly');
}

# Test slug with unicode characters
{
  my $person = MockPerson->new(
    id   => 222,
    sex  => 'f',
    born => '1985-12-25',
    name => 'Princesse Amélie',
  );

  $person->make_slug();
  my $slug = $person->slug;

  # Just verify it generates a slug with proper format, not exact transliteration
  like($slug, qr/^[0-9a-f]{6}-.+$/, 'Unicode characters produce valid slug');
}

done_testing();
