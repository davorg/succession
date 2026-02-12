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

use feature 'state';

sub get_schema {
  state $sch;

  my $dbfile = $ENV{SUCC_DB_PATH} // '/app/data/los.sqlite';
  my $dsn    = $ENV{SUCC_DSN} // "dbi:SQLite:dbname=$dbfile;mode=ro;immutable=1";

  $sch //= __PACKAGE__->connect(
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


__PACKAGE__->meta->make_immutable(inline_constructor => 0);
1;
