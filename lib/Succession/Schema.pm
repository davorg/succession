use utf8;
package Succession::Schema;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use Moose;
use MooseX::MarkAsMethods autoclean => 1;
extends 'DBIx::Class::Schema';

__PACKAGE__->load_namespaces;


# Created by DBIx::Class::Schema::Loader v0.07045 @ 2016-12-04 17:40:32
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:cqEWNsPVtEZ+VfMbuLt1MQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration

sub get_schema {
  my @errors;
  foreach (qw[SUCC_DB_HOST SUCC_DB_NAME SUCC_DB_USER SUCC_DB_PASS]) {
    push @errors, $_ unless defined $ENV{$_};
  }

  if (@errors) {
    die 'Please set the following environment variables: ',
        join(', ', @errors), "\n";
  }

  return __PACKAGE__->connect(
    "dbi:mysql:host=$ENV{SUCC_DB_HOST};database=$ENV{SUCC_DB_NAME}",
    $ENV{SUCC_DB_USER}, $ENV{SUCC_DB_PASS},
  );
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);
1;
