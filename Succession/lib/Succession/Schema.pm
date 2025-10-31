use utf8;
package Succession::Schema;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use Moose;
use MooseX::MarkAsMethods autoclean => 1;
extends 'DBIx::Class::Schema';

__PACKAGE__->load_components("Schema::ResultSetNames");

__PACKAGE__->load_namespaces;


# Created by DBIx::Class::Schema::Loader v0.07053 @ 2025-09-25 12:04:28
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:B7H4cY8h0acwWlCz89HTXA


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

  my $dsn = "dbi:mysql:host=$ENV{SUCC_DB_HOST};database=$ENV{SUCC_DB_NAME}";
  if ($ENV{SUCC_DB_PORT}) {
    $dsn .= ";port=$ENV{SUCC_DB_PORT}";
  }

  my $sch = __PACKAGE__->connect(
    $dsn, $ENV{SUCC_DB_USER}, $ENV{SUCC_DB_PASS},
    { mysql_enable_utf8 => 1, quote_char => '`' },
  );

  # For caching.
  $DBIx::Class::ResultSourceHandle::thaw_schema = $sch;

  return $sch;
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);
1;
