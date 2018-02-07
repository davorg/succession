package Succession::Model;

use strict;
use warnings;

use Moose;
use DateTime;
use CHI;
use Succession::Schema;

has schema => (
  is => 'ro',
  lazy_build => 1,
  isa => 'Succession::Schema',
);

sub _build_schema {
  return Succession::Schema->get_schema;
}

has sovereign_rs => (
  is => 'ro',
  isa => 'DBIx::Class::ResultSet',
  lazy_build =>  1,
  handles => [ qw(sovereign_on_date) ],
);

sub _build_sovereign_rs {
  return $_[0]->schema->resultset('Sovereign');
}

has change_date_rs => (
  is => 'ro',
  isa => 'DBIx::Class::ResultSet',
  lazy_build =>  1,
);

sub _build_change_date_rs {
  return $_[0]->schema->resultset('ChangeDate');
}

has cache => (
  is => 'ro',
  isa => 'CHI::Driver::Memcached',
  lazy_build => 1,
);

sub _build_cache {
  return CHI->new(
    driver => 'Memcached',
    namespace => 'succession',
    servers => [ 'localhost:11211' ],
    debug => 0,
    compress_threshold => 10_000,
  );
}

# sub sovereign_on_date {
#   my $seslf = shift;
#   my ($date) = @_;
#
#   return $self->sovereign_rs->sovereign_on_date($date);
# }

sub succession_on_date {
  my $self = shift;
  my ($date) = @_;

  my $succession = $self->cache->compute(
    'succ' . $date->ymd, undef,
    sub {
      [ $self->sovereign_on_date($date)->succession_on_date($date) ]
    },
  );

  return $succession;
}

sub get_succession {
  my $self = shift;

  my $succ = {
    sovereign => $self->sovereign->name,
  };

  for (@{$self->succession}) {
    push @{ $succ->{succ} }, $_->name;
  }

  return $succ;
}

sub get_succession_json {
  my $self = shift;

  my $succ = {
    sovereign => $self->sovereign->name,
  };

  my $i = 1;
  my @succ = map {{
    number => $i++,
    name   => $_->name,
    born   => $_->born->ymd,
    age    => $_->age_on_date,
  }} @{ $self->succession };

  $succ->{successors} = \@succ;

  return encode_json($succ);
}

sub get_canonical_date {
  my $self = shift;
  my ($date) = @_;

  my $canonical_date = $self->cache->compute(
    'canon' . $date->ymd, undef,
    sub {
      my $search_date =
        $self->schema->storage->datetime_parser->format_datetime($date);

      my $canon_date = $self->get_prev_change_date($date, 1);

      # TODO: Remove hack!
      return '' unless $canon_date;

      my $max_date = $self->change_date_rs->get_column('change_date')->max;

      if ($canon_date->change_date->strftime('%Y-%m-%d') eq $max_date) {
        return '';
      } else {
        return $canon_date->change_date->strftime('%Y-%m-%d');
      }
    }
  );

  return $canonical_date;
}

sub get_prev_change_date {
  my $self = shift;
  my ($date, $include_curr) = @_;

  my $prev_date = $self->cache->compute(
    'prev_change' . $date->ymd, undef,
    sub {
      my $search_date =
        $self->schema->storage->datetime_parser->format_datetime($date);

      my $cmp = ($include_curr ? '<=' : '<');

      my ($prev_date) = $self->change_date_rs->search({
        change_date => { $cmp, $search_date },
      },{
        order_by => { -desc => 'change_date' },
      });

      return $prev_date;
    });

  return $prev_date;
}

sub get_next_change_date {
  my $self = shift;
  my ($date, $include_curr) = @_;

  my $next_date = $self->cache->compute(
    'next_change' . $date->ymd, undef,
    sub {
      my $search_date =
        $self->schema->storage->datetime_parser->format_datetime($date);

      my $cmp = ($include_curr ? '>=' : '>');

      my ($next_date) = $self->change_date_rs->search({
        change_date => { $cmp, $search_date },
      },{
        order_by => { -asc => 'change_date' },
      });

      return $next_date;
    });

    return $next_date;
}

sub get_changes_on_date {
  my $self = shift;
  my ($date) = @_;

  my $date_changes = $self->cache->compute(
    'changes' . $date->ymd, undef,
    sub {
      my $search_date =
        $self->schema->storage->datetime_parser->format_datetime($date);

      my $changes = { count => 0 };

      return $changes
        unless $self->schema->resultset('ChangeDate')->search({
          change_date => $search_date,
        });

      my $person_rs    = $self->schema->resultset('Person');
      my $exclusion_rs = $self->schema->resultset('Exclusion');

      for (qw[born died]) {
        $changes->{person}{$_} = [ $person_rs->search({$_ => $search_date}) ];
        $changes->{count} += @{$changes->{person}{$_}};
      }

      for (qw[start end]) {
        $changes->{exclusion}{$_} = [ $exclusion_rs->search({$_ => $search_date}) ];
        $changes->{count} += @{$changes->{exclusion}{$_}};
      }

      return $changes;
    });

  return $date_changes;
}

1;
