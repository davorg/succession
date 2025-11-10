package Succession::Model;

use strict;
use warnings;

use Moose;
use DateTime;
use CHI;
use Path::Tiny;
use JSON::MaybeXS qw(decode_json);
use Digest::SHA qw(sha1_hex);
use Time::Piece;
use Succession::Schema;

has schema => (
  is => 'ro',
  builder => '_build_schema',
  isa => 'Succession::Schema',
);

sub _build_schema {
  return Succession::Schema->get_schema;
}

has [ qw[sovereign_rs person_rs] ] => (
  is => 'ro',
  isa => 'DBIx::Class::ResultSet',
  lazy_build =>  1,
);

sub _build_sovereign_rs {
  return $_[0]->schema->resultset('Sovereign');
}

sub _build_person_rs {
  return $_[0]->schema->resultset('Person');
}

has change_date_rs => (
  is => 'ro',
  isa => 'DBIx::Class::ResultSet',
  lazy_build =>  1,
);

sub _build_change_date_rs {
  return $_[0]->schema->resultset('ChangeDate');
}

has cache_servers => (
  is => 'ro',
  isa => 'ArrayRef',
  lazy_build => 1,
);

sub _build_cache_servers {
  my $server = $ENV{SUCC_CACHE_SERVER} // 'localhost';
  my $port   = $ENV{SUCC_CACHE_PORT}   // 11_211;

  return [ "$server:$port" ];
}

has cache => (
  is => 'ro',
  isa => 'CHI::Driver::Memcached',
  lazy_build => 1,
);

sub _build_cache {
  my $self = shift;

  return CHI->new(
    driver => 'Memcached',
    namespace => 'succession',
    servers => $self->cache_servers,
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
    monarch => 'George IV',
    dates => [{
      date => DateTime->new(year => 1820, month =>  1, day => 29),
      desc => "Start of reign",
    }]}, {
    monarch => 'William IV',
    dates => [{
      date => DateTime->new(year => 1830, month =>  6, day => 26),
      desc => "Start of reign",
    }]}, {
    monarch => 'Victoria',
    dates => [{
      date => DateTime->new(year => 1837, month =>  6, day => 20),
      desc => "Start of reign",
    }, {
      date => DateTime->new(year => 1862, month =>  6, day => 20),
      desc => "Silver Jubilee",
    }, {
      date => DateTime->new(year => 1877, month =>  6, day => 20),
      desc => "Ruby Jubilee",
    }, {
      date => DateTime->new(year => 1887, month =>  6, day => 20),
      desc => "Golden Jubilee",
    }, {
      date => DateTime->new(year => 1897, month =>  6, day => 20),
      desc => "Diamond Jubilee",
    }]}, {
    monarch => 'Edward VII',
    dates => [{
      date => DateTime->new(year => 1901, month =>  1, day => 22),
      desc => "Start of reign",
    }]}, {
    monarch => 'George V',
    dates => [{
      date => DateTime->new(year => 1910, month =>  5, day =>  6),
      desc => "Start of reign",
    }, {
      date => DateTime->new(year => 1935, month =>  5, day =>  6),
      desc => "Silver Jubilee",
    }]}, {
    monarch => 'Edward VIII',
    dates => [{
      date => DateTime->new(year => 1936, month =>  1, day => 20),
      desc => "Start of reign",
    }]}, {
    monarch => 'George VI',
    dates => [{
      date => DateTime->new(year => 1936, month => 12, day => 11),
      desc => "Start of reign",
    }]}, {
    monarch => 'Elizabeth II',
    dates => [{
      date => DateTime->new(year => 1952, month =>  2, day =>  6),
      desc => "Start of reign",
    }, {
      date => DateTime->new(year => 1977, month =>  2, day =>  6),
      desc => "Silver Jubilee",
    }, {
      date => DateTime->new(year => 1992, month =>  2, day =>  6),
      desc => "Ruby Jubilee",
    }, {
      date => DateTime->new(year => 2002, month =>  2, day =>  6),
      desc => "Golden Jubilee",
    }, {
      date => DateTime->new(year => 2012, month =>  2, day =>  6),
      desc => "Diamond Jubilee",
    }, {
      date => DateTime->new(year => 2017, month =>  2, day =>  6),
      desc => "Sapphire Jubilee",
    }, {
      date => DateTime->new(year => 2022, month =>  2, day =>  6),
      desc => "Platinum Jubilee",
    }]}, {
    monarch => 'Charles III',
    dates => [{
      date => DateTime->new(year => 2022, month => 9, day => 8),
      desc => 'Start of reign',
    }],
  }];
}

sub sovereign_on_date {
  my $self = shift;
  my ($date) = @_;

  $date //= $self->date;

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

  $date //= $self->date;

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

sub get_succession_data {
  my $self = shift;
  my ($date, $count) = @_;

  my $sov = $self->sovereign_on_date($date)->person;

  my $succ = {
    date      => $date->ymd,
    sovereign => {
      name => $sov->name,
      born => $sov->born->ymd,
      age  => $sov->age_on_date,
      slug => $sov->slug,
    },
  };

  my $i = 1;
  my @succ = map {{
    number => $i++,
    name   => $_->name,
    born   => $_->born->ymd,
    age    => $_->age_on_date,
    slug   => $_->slug,
  }} @{ $self->succession_on_date($date) };

  $#succ = $count - 1 if $#succ >= $count;

  $succ->{successors} = \@succ;

  return $succ;
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

  my @changes;

  foreach ($date->clone->subtract(days => 1),
           $date,
           $date->clone->add(days => 1)) {
    my @date_changes = $self->cache->compute(
        'changes|' . $_->ymd, undef,
        sub {
          my $search_date =
            $self->schema->storage->datetime_parser->format_datetime($_);

          return $self->schema->resultset('ChangeDate')->search({
            change_date => $search_date,
          })->all;
      });

      push @changes, @date_changes;
    }

  return \@changes;
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

sub get_person_from_slug {
  my $self = shift;
  my ($slug) = @_;

  my $person = $self->cache->compute(
    'person|' . $slug, undef,
    sub {
      return $self->schema->resultset('Person')->find_by_slug($slug);
    }
  );

  return $person;
}

sub get_all_changes {
  my $self = shift;

  return $self->cache->compute(
    'changes', undef,
    sub {
      return [ $self->schema->resultset('ChangeDate')->all ],
    }
  );
}

sub get_anniveraries {
  my $self = shift;

  my $anniversaries = $self->sovereign_rs->anniversaries;
  my $birthdays     = $self->person_rs->birthdays;

  return {
    anniversaries => $anniversaries,
    birthdays     => $birthdays,
  };
}

sub http_date {
  return gmtime(shift || time)->strftime('%a, %d %b %Y %H:%M:%S GMT');
}

# Load + cache shop.json (Memcached) with mtime-based invalidation
sub get_shop_data {
  my $self = shift;

  my $json_path = path('Succession', 'public', 'var', 'shop.json');
  my $mtime     = $json_path->stat ? $json_path->stat->mtime : 0;

  # cache key includes mtime — if file changes, cache miss
  my $key = "shopjson:$mtime";

  my $cached = $self->cache->get($key);
  return ($cached->{data}, $cached->{etag}, $cached->{last_mod})
    if $cached;

  # Read + parse JSON
  my $raw = $json_path->slurp_raw;
  my $shop = decode_json($raw);

  # Compute ETag from content
  my $etag = qq{"} . sha1_hex($raw) . qq{"};
  my $last_mod = http_date($mtime);

  # If you want to append amazon_tag centrally to links later, you can,
  # but you said you’ll use an Amazon button helper from ASIN — so no need.

  $self->cache->set($key, { data => $shop, etag => $etag, last_mod => $last_mod }, 60 * 10);
  return ($shop, $etag, $last_mod);
}

sub db_ver {
  my $self = shift;

  my $driver = $self->schema->storage->dbh->{Driver}{Name};

  my $info = "DB Driver: $driver";

  if ($driver eq 'SQLite') {
    $info .= ', version: ' . $self->schema->storage->dbh->{sqlite_version};
  }

  return $info;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
