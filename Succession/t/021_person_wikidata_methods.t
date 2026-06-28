use strict;
use warnings;

use Test::More;

use Succession::Schema::Result::Person;

for my $method (qw[wikidata image_url short_bio]) {
  ok(
    !Succession::Schema::Result::Person->can($method),
    "Person result does not expose $method",
  );
}

done_testing();
