package Succession::Model;

=head1 NAME

Succession::Model - Application data access and cached view data

=head1 DESCRIPTION

This class is the application's boundary around DBIx::Class, cache-backed
lookups, and the small external or file-backed data sources used by routes.
Methods are grouped below by responsibility so that new queries have an
obvious home.

=head1 ATTRIBUTES

=over 4

=item C<schema>

The L<Succession::Schema> used for database access.

=item C<sovereign_rs>, C<person_rs>, C<change_date_rs>

Convenience result sets for the tables queried directly by this model.

=item C<cache>, C<cache_servers>

The CHI cache and its configured server list.

=item C<relationship>, C<relationship_people>

The genealogy engine and the in-memory person graph used by it.

=item C<feed_url>, C<feed_timeout>, C<feed_ttl>, C<feed_stale_ttl>,
C<feed_failure_ttl>, C<feed_fetcher>

Configuration and injectable fetcher for the cached blog feed.

=item C<interesting_dates>

Curated reign and jubilee dates displayed by the application.

=back

=head1 METHODS

=head2 Blog feed

=over 4

=item C<get_feed_entries>

Returns cached blog-feed entries, using stale data when a refresh fails.

=back

=head2 Succession

=over 4

=item C<sovereign_on_date($date)>

Returns the sovereign in office on a date.

=item C<succession_on_date($date)>

Returns the ordered people in the line of succession on a date.

=item C<get_succession>

Returns the current sovereign and succession as a simple name structure.

=item C<get_succession_data($date, $count)>

Builds the dated succession view data, limited to C<$count> successors.

=back

=head2 Change dates

=over 4

=item C<get_canonical_date($date)>

Returns the canonical change date for a dated succession page.

=item C<get_prev_change_date($date, $include_current)>

Returns the change date immediately before the supplied date.

=item C<get_next_change_date($date, $include_current)>

Returns the change date immediately after the supplied date.

=item C<get_changes_on_date($date)>

Returns change records for the day before, the day itself, and the day after.

=item C<get_all_changes>

Returns every change date with the related people and titles prefetched.

=back

=head2 People and relationships

=over 4

=item C<get_relationship_between_people($person1, $person2)>

Calculates the genealogical relationship between two people.

=item C<get_person_from_slug($slug)>

Finds and caches the person identified by a page slug.

=item C<get_person_page_data($person)>

Builds the prefetched titles, positions, relatives, and exclusions for a
person page.

=back

=head2 Other page data

=over 4

=item C<get_anniversaries>

Returns sovereign anniversaries and birthdays for the anniversaries page.

=item C<get_shop_data($json_path)>

Reads and caches shop JSON, returning its data and HTTP validator values.

=item C<get_reference_menu($directory)>

Builds the cached reference-page navigation from Markdown files.

=item C<db_ver>

Returns a human-readable description of the active database driver.

=back

=head1 INTERNAL HELPERS

Builder methods and file-format helpers are private implementation details and
are not part of the public method list above.

=cut

use v5.32;
use Moose;
use experimental qw[signatures]; # After Moose because Moose turns all warnings on
use DateTime;
use CHI;
use Path::Tiny;
use Try::Tiny;
use JSON::MaybeXS qw(decode_json);
use Digest::SHA qw(sha1_hex);
use HTTP::Tiny;
use Time::Piece;
use XML::Feed;
use Genealogy::Relationship;
use Succession (); # for version number to use in cache
use Succession::RelationshipPerson;
use Succession::Schema;

# Database access

has schema => (
  is => 'ro',
  builder => '_build_schema',
  isa => 'Succession::Schema',
);

sub _build_schema($) {
  return Succession::Schema->get_schema;
}

has [ qw[sovereign_rs person_rs] ] => (
  is => 'ro',
  isa => 'DBIx::Class::ResultSet',
  lazy_build =>  1,
);

sub _build_sovereign_rs($self) {
  return $self->schema->resultset('Sovereign');
}

sub _build_person_rs($self) {
  return $self->schema->resultset('Person');
}

has change_date_rs => (
  is => 'ro',
  isa => 'DBIx::Class::ResultSet',
  lazy_build =>  1,
);

sub _build_change_date_rs($self) {
  return $self->schema->resultset('ChangeDate');
}

# Genealogical relationships

has relationship => (
  is => 'ro',
  isa => 'Genealogy::Relationship',
  lazy_build => 1,
);

sub _build_relationship($) {
  return Genealogy::Relationship->new;
}

has relationship_people => (
  is => 'ro',
  isa => 'HashRef',
  lazy_build => 1,
);

sub _build_relationship_people($self) {
  my @rows = $self->person_rs->search(undef, {
    columns => [ qw(id parent sex) ],
  })->all;

  my %people = map {
    $_->id => Succession::RelationshipPerson->new(
      id     => $_->id,
      gender => $_->sex,
    )
  } @rows;

  for my $row (@rows) {
    my $parent_id = $row->get_column('parent');
    next unless defined $parent_id;

    die "Person $parent_id is missing from the relationship graph"
      unless exists $people{$parent_id};

    $people{$row->id}->parent($people{$parent_id});
  }

  return \%people;
}

# Caching

has cache_servers => (
  is => 'ro',
  isa => 'ArrayRef',
  lazy_build => 1,
);

sub _build_cache_servers($) {
  my $server = $ENV{SUCC_CACHE_SERVER} // 'localhost';
  my $port   = $ENV{SUCC_CACHE_PORT}   // 11_211;

  return [ "$server:$port" ];
}

has cache => (
  is => 'ro',
  isa => 'CHI::Driver',
  lazy_build => 1,
);

sub _build_cache( $self ) {
  my $driver = $ENV{SUCC_CACHE_DRIVER} // 'FastMmap';

  my %common = (
    namespace => "succession-$Succession::VERSION",
  );

  try {
    if ($driver eq 'Memcached') {
      return CHI->new(
        driver => 'Memcached',
        servers => $self->cache_servers,
        compress_threshold => 10_000,
        %common,
      );
    } elsif ($driver eq 'FastMmap') {
      my $root_dir  = $ENV{SUCC_CACHE_DIR}  // '/tmp/chi-cache';
      my $cache_size = $ENV{SUCC_CACHE_SIZE} // '64m';  # FastMmap/Cache::FastMmap syntax

      return CHI->new(
        driver     => 'FastMmap',
        root_dir   => $root_dir,
        cache_size => $cache_size,
        unlink_on_exit => 0,
        %common,
      );
    } else {
      return CHI->new(
        driver => $driver,
        %common,
      );
    };
  } catch {
    warn "Cache initialisation failed for driver '$driver': $_\n",
         "Falling back to Null cache.\n";

    return CHI->new(
      driver => 'Null',
      %common,
    );
  }
}

# Blog feed

has feed_url => (
  is => 'ro',
  isa => 'Str',
  default => 'https://blog.lineofsuccession.co.uk/feed',
);

has feed_timeout => (
  is => 'ro',
  isa => 'Num',
  default => 3,
);

has feed_ttl => (
  is => 'ro',
  isa => 'Int',
  default => 15 * 60,
);

has feed_stale_ttl => (
  is => 'ro',
  isa => 'Int',
  default => 7 * 24 * 60 * 60,
);

has feed_failure_ttl => (
  is => 'ro',
  isa => 'Int',
  default => 60,
);

has feed_fetcher => (
  is => 'ro',
  isa => 'CodeRef',
  lazy_build => 1,
);

sub _build_feed_fetcher($self) {
  my $url = $self->feed_url;
  my $http = HTTP::Tiny->new(
    timeout => $self->feed_timeout,
    agent   => "succession/$Succession::VERSION",
  );

  return sub {
    my $response = $http->get($url);
    die "HTTP $response->{status} $response->{reason}"
      unless $response->{success};

    return $response->{content};
  };
}

sub get_feed_entries($self) {
  my $fresh_key = 'blog_feed_entries_v1';
  my $stale_key = 'blog_feed_entries_stale_v1';

  my $cached = $self->cache->get($fresh_key);
  return $cached if ref $cached eq 'ARRAY';

  my $stale = $self->cache->get($stale_key);
  $stale = undef unless ref $stale eq 'ARRAY';

  my ($entries, $error);

  try {
    my $fetcher = $self->feed_fetcher;
    my $xml = $fetcher->();
    my $feed = XML::Feed->parse(\$xml)
      or die 'XML parse failed: ' . (XML::Feed->errstr // 'unknown error');

    $entries = [ map {
      my $title = $_->title;
      my $link  = $_->link;

      {
        title => defined $title ? "$title" : '',
        link  => defined $link  ? "$link"  : '',
      }
    } $feed->entries ];
  } catch {
    $error = $_;
  };

  if ($error) {
    chomp $error;
    warn "Blog feed refresh failed: $error\n";
    $entries = $stale // [];

    # Avoid retrying the remote feed on every request during an outage.
    $self->cache->set($fresh_key, $entries, $self->feed_failure_ttl);
    return $entries;
  }

  $self->cache->set($fresh_key, $entries, $self->feed_ttl);
  $self->cache->set($stale_key, $entries, $self->feed_stale_ttl);

  return $entries;
}

# Curated historical dates

has interesting_dates => (
  is => 'ro',
  isa => 'ArrayRef',
  lazy_build => 1,
);

sub _build_interesting_dates($) {
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

# Succession queries

sub sovereign_on_date($self, $date = undef) {
  $date //= $self->date;

  my $sovereign = $self->cache->compute(
    'sov|' . $date->ymd, undef,
    sub {
      $self->sovereign_rs->sovereign_on_date($date);
    },
  );

  return $sovereign;
}

sub succession_on_date($self, $date = undef) {
  $date //= $self->date;

  my $succession = $self->cache->compute(
    'succ|' . $date->ymd, undef,
    sub {
      my $succ = $self->schema->succession_periods->succession_on_date($date);
      [ $succ ? map { $_->person } $succ->succession_entries : () ];
    },
  );

  return $succession;
}

sub get_succession($self) {
  my $succ = {
    sovereign => $self->sovereign->name,
  };

  for (@{$self->succession}) {
    push @{ $succ->{succ} }, $_->name;
  }

  return $succ;
}

sub get_succession_data($self, $date, $count) {
  my $sov = $self->sovereign_on_date($date)->person;

  my $succ = {
    date      => $date->ymd,
    sovereign => {
      name => $sov->name,
      born => $sov->born->ymd,
      age  => $sov->age_on_date($date),
      slug => $sov->slug,
    },
  };

  my $i = 1;
  my @succ = map {{
    number => $i++,
    name   => $_->name,
    born   => $_->born->ymd,
    age    => $_->age_on_date($date),
    slug   => $_->slug,
  }} @{ $self->succession_on_date($date) };

  $#succ = $count - 1 if $#succ >= $count;

  $succ->{successors} = \@succ;

  return $succ;
}

# Change-date queries

sub get_canonical_date($self, $date) {
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

sub get_prev_change_date($self, $date, $include_curr = 0) {
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

sub get_next_change_date($self, $date, $include_curr = 0) {
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

sub get_changes_on_date($self, $date) {
  return $self->cache->compute(
    'changes_around|' . $date->ymd, undef,
    sub {
      my $dtf = $self->schema->storage->datetime_parser;
      my @dates = map {
        $dtf->format_datetime($_)
      } (
        $date->clone->subtract(days => 1),
        $date,
        $date->clone->add(days => 1),
      );

      return [ $self->change_date_rs->search({
        change_date => { -in => \@dates },
      }, {
        order_by => { -asc => 'change_date' },
      })->all ];
    },
  );
}

sub get_all_changes($self) {
  return $self->cache->compute(
    'changes_v2', undef,
    sub {
      return [ $self->change_date_rs->search(undef, {
        order_by => [ 'me.change_date', 'changes.id' ],
        prefetch => {
          changes => {
            person => 'titles',
          },
        },
      })->all ];
    }
  );
}

# People and relationships

sub get_relationship_between_people($self, $person1, $person2) {
  my $relationship = $self->cache->compute(
    'rel|' . $person1->id . '|' . $person2->id, undef,
    sub {
      my $people = $self->relationship_people;
      my $rel_person1 = $people->{$person1->id}
        or die 'Person ' . $person1->id . ' is missing from the relationship graph';
      my $rel_person2 = $people->{$person2->id}
        or die 'Person ' . $person2->id . ' is missing from the relationship graph';

      return $self->relationship->get_relationship($rel_person1, $rel_person2);
    }
  );

  return $relationship;
}

sub get_person_from_slug($self, $slug) {
  my $person = $self->cache->compute(
    'person_page_v2|' . $slug, undef,
    sub {
      return $self->schema->resultset('Person')->find_by_slug($slug);
    }
  );

  return $person;
}

sub get_person_page_data($self, $person) {
  my @titles = sort {
    ($a->start ? $a->start->ymd : '') cmp ($b->start ? $b->start->ymd : '')
  } $person->titles;

  my @exclusions = sort {
    ($a->start ? $a->start->ymd : '') cmp ($b->start ? $b->start->ymd : '')
  } $person->exclusions;

  my $position_rs = $person->succession_entries_rs;
  my @positions   = $position_rs->order_by_date->all;

  my @children = $person->children_rs->order_by_age->search(undef, {
    prefetch => 'titles',
  })->all;

  my $siblings_rs = $person->siblings;
  my @siblings = $siblings_rs
    ? $siblings_rs->search(undef, { prefetch => 'titles' })->all
    : ();

  return {
    titles              => \@titles,
    positions           => \@positions,
    collapsed_positions => $position_rs->collapse_entries(\@positions),
    children            => \@children,
    siblings            => \@siblings,
    exclusions          => \@exclusions,
  };
}

# Anniversary page

sub get_anniversaries($self) {
  my $anniversaries = $self->sovereign_rs->anniversaries;
  my $birthdays     = $self->person_rs->birthdays;

  return {
    anniversaries => $anniversaries,
    birthdays     => $birthdays,
  };
}

# Shop data

sub http_date($epoch) {
  return gmtime($epoch || time)->strftime('%a, %d %b %Y %H:%M:%S GMT');
}

# Load + cache shop.json (Memcached) with mtime-based invalidation
sub get_shop_data($self, $json_path) {
  $json_path = path($json_path);
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

# Reference pages

sub get_reference_menu($self, $ref_dir) {
  return $self->cache->compute('ref_menu', undef, sub {
    my @menu;
    for my $file (sort { $a->basename cmp $b->basename } $ref_dir->children(qr/\.md$/)) {
      my $slug  = $file->basename('.md');
      my $title = _ref_page_title($file->slurp_utf8) // $slug;
      push @menu, { slug => $slug, title => $title };
    }
    return \@menu;
  });
}

sub _ref_page_title {
  my ($content) = @_;
  if ($content =~ /\A---\n(.*?)\n---\n/s) {
    my ($title) = $1 =~ /^title:\s*(.+?)\s*$/m;
    return $title;
  }
  return undef;
}

# Diagnostics

sub db_ver( $self ) {
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
