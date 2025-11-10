package Succession::Schema::ResultSet::Sovereign;

use strict;
use warnings;
use experimental 'signatures';

use parent 'DBIx::Class::ResultSet';

sub sovereign_on_date( $self, $date ) {
  $date = $self->result_source->schema->storage->
          datetime_parser->format_datetime($date);

  return $self->find({
    start => { '<=' => $date },
    end   => [ { '>' => $date }, undef ],
  }, {
    prefetch => qw[person],
  });
}

sub _is_sqlite( $self ) {
  return $self->result_source->schema->storage->dbh->{Driver}{Name} eq 'SQLite';
}

sub anniversaries( $self ) {
  my ($where_sql, @order);
  if ($self->_is_sqlite) {
    $where_sql = q{
      (
        strftime('%m-%d', start)
          BETWEEN strftime('%m-%d','now')
              AND strftime('%m-%d','now','+7 day')
      )
      OR
      (
        strftime('%m-%d','now') > strftime('%m-%d','now','+7 day')
        AND (
          strftime('%m-%d', start) >= strftime('%m-%d','now')
          OR  strftime('%m-%d', start) <= strftime('%m-%d','now','+7 day')
        )
      )
    };
    @order = (
      \q{CAST(strftime('%m', start) AS INTEGER)},
      \q{CAST(strftime('%d', start) AS INTEGER)},
      \q{CAST(strftime('%Y', start) AS INTEGER)},
    );
  } else {
    $where_sql = q{
      (
        DATE_FORMAT(start, '%m-%d')
          BETWEEN DATE_FORMAT(CURDATE(), '%m-%d')
              AND DATE_FORMAT(DATE_ADD(CURDATE(), INTERVAL 7 DAY), '%m-%d')
      )
      OR
      (
        DATE_FORMAT(CURDATE(), '%m-%d') > DATE_FORMAT(DATE_ADD(CURDATE(), INTERVAL 7 DAY), '%m-%d')
        AND (
          DATE_FORMAT(start, '%m-%d') >= DATE_FORMAT(CURDATE(), '%m-%d')
          OR  DATE_FORMAT(start, '%m-%d') <= DATE_FORMAT(DATE_ADD(CURDATE(), INTERVAL 7 DAY), '%m-%d')
        )
      )
    };
    @order = ( \q{MONTH(start)}, \q{DAY(start)}, \q{YEAR(start)} );
  }

  my @rows = $self->search(
    [ \ $where_sql ],
    {
      rows     => 200,                         # optional
      order_by => { -asc => \@order },
    },
  )->all;

  return \@rows;
}

1;
