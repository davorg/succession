package Succession::Schema::ResultSet::Person;

use strict;
use warnings;

use parent 'DBIx::Class::ResultSet';

sub order_by_age {
  my $self = shift;

  return $self->search(undef, { order_by => 'born' });
}

sub find_by_slug {
  my $self = shift;
  my ($slug) = @_;

  $slug =~ s/-.*//;

  return $self->find({
    slug => { like => "$slug-%" },
  });
}

sub _is_sqlite {
  my $self = shift;
  return $self->result_source->schema->storage->dbh->{Driver}{Name} eq 'SQLite';
}

sub birthdays {
  my $self = shift;

  my ($where_sql, @bind, @order);
  if ($self->_is_sqlite) {
    # SQLite: use strftime + date('now', '+7 day')
    $where_sql = q{
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
    @order = (
      \q{CAST(strftime('%m', born) AS INTEGER)},
      \q{CAST(strftime('%d', born) AS INTEGER)},
      \q{CAST(strftime('%Y', born) AS INTEGER)},
    );
  } else {
    # MySQL/MariaDB
    $where_sql = q{
      (
        DATE_FORMAT(born, '%m-%d')
          BETWEEN DATE_FORMAT(CURDATE(), '%m-%d')
              AND DATE_FORMAT(DATE_ADD(CURDATE(), INTERVAL 7 DAY), '%m-%d')
      )
      OR
      (
        DATE_FORMAT(CURDATE(), '%m-%d') > DATE_FORMAT(DATE_ADD(CURDATE(), INTERVAL 7 DAY), '%m-%d')
        AND (
          DATE_FORMAT(born, '%m-%d') >= DATE_FORMAT(CURDATE(), '%m-%d')
          OR  DATE_FORMAT(born, '%m-%d') <= DATE_FORMAT(DATE_ADD(CURDATE(), INTERVAL 7 DAY), '%m-%d')
        )
      )
    };
    @order = ( \q{MONTH(born)}, \q{DAY(born)}, \q{YEAR(born)} );
  }

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
