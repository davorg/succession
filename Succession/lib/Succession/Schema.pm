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
  # --- Branch 1: explicit SQLite if LOS_DB_PATH or LOS_DSN is set ---

  if ($ENV{SUCC_DSN} or $ENV{SUCC_DB_PATH}) {
    my $dbfile = $ENV{SUCC_DB_PATH} // '/app/data/los.sqlite';
    my $dsn    = $ENV{SUCC_DSN} // "dbi:SQLite:dbname=$dbfile;mode=ro;immutable=1";

    my $sch = __PACKAGE__->connect(
      $dsn, '', '',
      {
        sqlite_unicode => 1,
        quote_names    => 1,   # use "..." quoting in SQL
        on_connect_do  => [
          'PRAGMA foreign_keys = ON',
          'PRAGMA synchronous = OFF',  # safe for read-only
          'PRAGMA temp_store = MEMORY',
        ],
        RaiseError     => 1,
        AutoCommit     => 1,
      },
    );

    # For caching.
    $DBIx::Class::ResultSourceHandle::thaw_schema = $sch;
    return $sch;
  }

  # --- Branch 2: default to existing MySQL behaviour ---
  my @errors;
  for my $k (qw[SUCC_DB_HOST SUCC_DB_NAME SUCC_DB_USER SUCC_DB_PASS]) {
    push @errors, $k unless defined $ENV{$k};
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
    {
      mysql_enable_utf8mb4 => 1,  # modern MySQL UTF8
      quote_char           => '`',
      name_sep             => '.',
      RaiseError           => 1,
      AutoCommit           => 1,
    },
  );

  # For caching.
  $DBIx::Class::ResultSourceHandle::thaw_schema = $sch;
  return $sch;
}


__PACKAGE__->meta->make_immutable(inline_constructor => 0);
1;
