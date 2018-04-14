package Succession::Model;

use strict;
use warnings;

use Moose;
use DateTime;
use CHI;
use Succession::Schema;

has schema => (
  is => 'ro',
  builder => '_build_schema',
  isa => 'Succession::Schema',
);

sub _build_schema {
  return Succession::Schema->get_schema;
}

has sovereign_rs => (
  is => 'ro',
  isa => 'DBIx::Class::ResultSet',
  lazy_build =>  1,
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

has interesting_dates => (
  is => 'ro',
  isa => 'ArrayRef',
  lazy_build => 1,
);

sub _build_interesting_dates {
  return [{
    date => DateTime->new(year => 1837, month =>  6, day => 20),
    desc => "Start of Victoria's reign",
  }, {
    date => DateTime->new(year => 1862, month =>  6, day => 20),
    desc => "Silver Jubilee of Victoria",
  }, {
    date => DateTime->new(year => 1887, month =>  6, day => 20),
    desc => "Golden Jubilee of Victoria",
  }, {
    date => DateTime->new(year => 1901, month =>  1, day => 22),
    desc => "Start of Edward VII's reign",
  }, {
    date => DateTime->new(year => 1910, month =>  5, day =>  6),
    desc => "Start of George V's reign",
  }, {
    date => DateTime->new(year => 1935, month =>  5, day =>  6),
    desc => "Silver Jubilee of George V",
  }, {
    date => DateTime->new(year => 1936, month =>  1, day => 20),
    desc => "Start of Edward VIII's reign",
  }, {
    date => DateTime->new(year => 1936, month => 12, day => 11),
    desc => "Start of George VI's reign",
  }, {
    date => DateTime->new(year => 1952, month =>  2, day =>  6),
    desc => "Start of Elizabeth II's reign",
  }, {
    date => DateTime->new(year => 1977, month =>  2, day =>  6),
    desc => "Silver Jubilee of Elizabeth II",
  }, {
    date => DateTime->new(year => 1992, month =>  2, day =>  6),
    desc => "Ruby Jubilee of Elizabeth II",
  }, {
    date => DateTime->new(year => 2002, month =>  2, day =>  6),
    desc => "Golden Jubilee of Elizabeth II",
  }, {
    date => DateTime->new(year => 2012, month =>  2, day =>  6),
    desc => "Diamond Jubilee of Elizabeth II",
  }, {
    date => DateTime->new(year => 2017, month =>  2, day =>  6),
    desc => "Sapphire Jubilee of Elizabeth II",
  }];
}

sub sovereign_on_date {
  my $self = shift;
  my ($date) = @_;

  my $sovereign = $self->cache->compute(
    'sov|' . $date->ymd, undef,
    sub {
      $self->sovereign_rs->sovereign_on_date($date);
    },
  );

  return $sovereign;
}

sub succession_on_date {
  my $self = shift;
  my ($date) = @_;

  my $succession = $self->cache->compute(
    'succ|' . $date->ymd, undef,
    sub {
      [ $self->sovereign_on_date($date)->succession_on_date($date) ];
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
    'canon|' . $date->ymd, undef,
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
  my ($date) = @_;
  my $include_curr = $_[1] // 0;

  my $prev_date = $self->cache->compute(
    "prev_change|$include_curr|" . $date->ymd, undef,
    sub {
      my $search_date =
        $self->schema->storage->datetime_parser->format_datetime($date);

      my $cmp = ($include_curr ? '<=' : '<');

      my ($pdate) = $self->change_date_rs->search({
        change_date => { $cmp, $search_date },
      },{
        order_by => { -desc => 'change_date' },
      });

      return $pdate;
    });

  return $prev_date;
}

sub get_next_change_date {
  my $self = shift;
  my ($date) = @_;
  my $include_curr = $_[1] // 0;

  my $next_date = $self->cache->compute(
    "next_change|$include_curr|" . $date->ymd, undef,
    sub {
      my $search_date =
        $self->schema->storage->datetime_parser->format_datetime($date);

      my $cmp = ($include_curr ? '>=' : '>');

      my ($ndate) = $self->change_date_rs->search({
        change_date => { $cmp, $search_date },
      },{
        order_by => { -asc => 'change_date' },
      });

      return $ndate;
    });

    return $next_date;
}

sub get_changes_on_date {
  my $self = shift;
  my ($date) = @_;

  my $date_changes = $self->cache->compute(
    'changes|' . $date->ymd, undef,
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

sub get_relationship_between_people {
  my $self = shift;
  my ($person1, $person2) = @_;

  my $relationship = $self->cache->compute(
    'rel|' . $person1->id . '|' . $person2->id, undef,
    sub {
      return $person1->relationship_with($person2);
    }
  );

  return $relationship;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
