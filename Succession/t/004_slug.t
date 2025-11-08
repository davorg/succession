use strict;
use warnings;

use Test::More;
use lib 'Succession/lib';

# Test the slug functionality in the actual Person.pm class

use Succession::Schema;

# Create an in-memory SQLite database for testing
my $schema = Succession::Schema->connect('dbi:SQLite:dbname=:memory:', '', '', {
  sqlite_unicode => 1,
  quote_names => 1,
  on_connect_do => ['PRAGMA foreign_keys = ON'],
  RaiseError => 1,
  AutoCommit => 1,
});

# Deploy the schema - create the necessary tables
$schema->deploy();

# Helper to create a person with a default title
sub create_test_person {
  my %args = @_;
  
  my $person = $schema->resultset('Person')->create({
    born => $args{born},
    died => $args{died},
    sex => $args{sex},
    parent => $args{parent},
  });
  
  # Add a default title (this is what the 'name' method uses)
  $person->add_to_titles({
    title => $args{name},
    is_default => 1,
  });
  
  return $person;
}

# Test make_slug with immutable fields
{
  my $person = create_test_person(
    born => '1982-06-21',
    sex  => 'm',
    name => 'Prince William',
  );

  $person->make_slug();
  my $slug1 = $person->slug;

  ok($slug1, 'Slug was generated');
  like($slug1, qr/^[0-9a-f]{6}-prince-william$/, 'Slug has correct format');

  # Get the hex part before changing the name
  my ($hex1) = $slug1 =~ /^([0-9a-f]{6})-/;

  # Change the name by updating the default title
  my $title = $person->titles({ is_default => 1 })->first;
  $title->update({ title => 'Duke of Cambridge' });
  
  # Regenerate slug - hex should stay the same
  $person->make_slug();
  my $slug2 = $person->slug;

  my ($hex2) = $slug2 =~ /^([0-9a-f]{6})-/;

  is($hex1, $hex2, 'Hex part stays the same when name changes');
  like($slug2, qr/^[0-9a-f]{6}-duke-of-cambridge$/, 'Name part updates correctly');
}

# Test that hex depends only on immutable fields
{
  my $person1 = create_test_person(
    born => '1988-08-08',
    sex  => 'f',
    name => 'Princess Beatrice',
  );

  my $person2 = create_test_person(
    born => '1988-08-08',
    sex  => 'f',
    name => 'Different Name',
  );

  $person1->make_slug();
  $person2->make_slug();

  my ($hex1) = $person1->slug =~ /^([0-9a-f]{6})-/;
  my ($hex2) = $person2->slug =~ /^([0-9a-f]{6})-/;

  # Same born date and sex, but different IDs (auto-increment)
  # So hex should be different
  isnt($hex1, $hex2, 'Different IDs produce different hex parts');
  
  # But if we create two people with same immutable fields and same ID
  # (which won't happen in practice), they would have same hex
  # This test just confirms the hex is based on id, sex, born
}

# Test regenerate_slug
{
  my $person = create_test_person(
    born => '1984-09-15',
    sex  => 'm',
    name => 'Prince Harry',
  );

  $person->make_slug();
  my $original_slug = $person->slug;
  my ($original_hex) = $original_slug =~ /^([0-9a-f]{6})-/;

  # Change the name by updating the default title
  my $title = $person->titles({ is_default => 1 })->first;
  $title->update({ title => 'Duke of Sussex' });
  
  # Use regenerate_slug
  $person->regenerate_slug();
  my $new_slug = $person->slug;
  my ($new_hex) = $new_slug =~ /^([0-9a-f]{6})-/;

  is($original_hex, $new_hex, 'regenerate_slug preserves hex part');
  like($new_slug, qr/^[0-9a-f]{6}-duke-of-sussex$/, 'regenerate_slug updates name part');
}

# Test regenerate_slug without existing slug
{
  my $person = create_test_person(
    born => '1990-01-01',
    sex  => 'f',
    name => 'Test Person',
  );

  # No slug set yet
  $person->regenerate_slug();
  ok(!defined $person->slug, 'regenerate_slug returns early if no slug exists');
}

# Test slug with special characters in name
{
  my $person = create_test_person(
    born => '1990-05-10',
    sex  => 'm',
    name => "Prince O'Brien-Smith",
  );

  $person->make_slug();
  my $slug = $person->slug;

  like($slug, qr/^[0-9a-f]{6}-prince-o-brien-smith$/, 'Special characters handled correctly');
}

# Test slug with unicode characters
{
  my $person = create_test_person(
    born => '1985-12-25',
    sex  => 'f',
    name => 'Princesse Amélie',
  );

  $person->make_slug();
  my $slug = $person->slug;

  # Just verify it generates a slug with proper format, not exact transliteration
  like($slug, qr/^[0-9a-f]{6}-.+$/, 'Unicode characters produce valid slug');
}

done_testing();
