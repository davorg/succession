package Succession::Schema::ResultSet::Person;

use strict;
use warnings;
use experimental 'signatures';

use parent 'DBIx::Class::ResultSet';

sub order_by_age( $self ) {
  return $self->search(undef, { order_by => 'born' });
}

sub find_by_slug( $self, $slug ) {
  $slug =~ s/-.*//;

  return $self->find({
    slug => { like => "$slug-%" },
  });
}

sub birthdays( $self ) {

  # SQLite: use strftime + date('now', '+7 day')
  my $where_sql = q{
    (
      strftime('%m-%d', born)
        BETWEEN strftime('%m-%d','now')
            AND strftime('%m-%d','now','+7 day')
    )
    OR
    (
      strftime('%m-%d','now') > strftime('%m-%d','now','+7 day')
      AND (
        strftime('%m-%d', born) >= strftime('%m-%d','now')
        OR  strftime('%m-%d', born) <= strftime('%m-%d','now','+7 day')
      )
    )
  };
  my @order = (
    \q{CAST(strftime('%m', born) AS INTEGER)},
    \q{CAST(strftime('%d', born) AS INTEGER)},
    \q{CAST(strftime('%Y', born) AS INTEGER)},
  );

  my @rows = $self->search(
    [ \ $where_sql ],
    {
      rows     => 200,                         # optional: cap
      order_by => { -asc => \@order },
    },
  )->all;

  return \@rows;
}

1;
