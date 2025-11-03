package Succession::WikiData::Entity;

use feature qw(signatures);
no warnings qw(experimental::signatures);
use utf8;

use Moo;
use HTTP::Tiny;
use Try::Tiny;
use JSON::MaybeXS ();

# ----------------------------
# Attributes
# ----------------------------
has qid => (
  is       => 'rw',        # may change after following redirects
  required => 1,
);

has data => ( is => 'rw' );        # full decoded JSON payload (last hop)
has entity => ( is => 'rw' );      # entity hashref for ->qid
has redirected_from => ( is => 'rw' );  # original QID if redirect happened

has http => (
  is      => 'ro',
  default => sub {
    HTTP::Tiny->new(
      agent        => "Succession-WikiData-Entity/0.04",
      timeout      => 20,
      max_redirect => 3,
    );
  },
);

has json => (
  is      => 'ro',
  default => sub { JSON::MaybeXS->new(utf8 => 1) },
);

# ----------------------------
# Build step: fetch & follow redirects once constructed
# ----------------------------
sub BUILD {
  my ($self, $args) = @_;
  $self->_fetch_and_follow_redirects();
}

# ----------------------------
# Fetch with redirect handling
# ----------------------------
sub _fetch_and_follow_redirects {
  my ($self) = @_;
  my $hops    = 0;
  my $current = $self->qid;
  my $from;

  while ($hops++ < 3) {
    my $url = "https://www.wikidata.org/wiki/Special:EntityData/$current.json";

    my $res;
    try {
      $res = $self->http->get($url);
    }
    catch {
      die "HTTP error fetching $url: $_";
    };

    die "HTTP $res->{status} $res->{reason} for $url" unless $res->{success};

    my $doc;
    try {
      $doc = $self->json->decode($res->{content});
    }
    catch {
      die "JSON decode failed for $current: $_";
    };

    # keep last raw document
    $self->data($doc);

    # Top-level redirects map
    if (   $doc->{redirects}
        && $doc->{redirects}{$current}
        && $doc->{redirects}{$current}{to}) {
      $from //= $current;
      $current = $doc->{redirects}{$current}{to};
      next;
    }

    # Normal case: entities->{$current}
    if ($doc->{entities} && $doc->{entities}{$current}) {
      $self->qid($current);
      $self->{redirected_from} = $from if defined $from && $from ne $current;
      $self->entity($doc->{entities}{$current});
      return;
    }

    # Implicit redirect: single different key in entities
    if ($doc->{entities}) {
      my @keys = keys %{ $doc->{entities} };
      if (@keys == 1 && $keys[0] ne $current) {
        $from //= $current;
        $current = $keys[0];
        next;
      }
    }

    die "Could not resolve entity for $current";
  }

  die "Exceeded redirect hops while fetching " . ($self->qid // '(undef)');
}

# ----------------------------
# Generic claim readers
# ----------------------------
sub _claims {
  my ($self, $prop) = @_;
  my $ent = $self->entity // return [];
  return $ent->{claims}{$prop} // [];
}

sub ids_for {
  my ($self, $prop) = @_;
  my @out;
  for my $st (@{ $self->_claims($prop) }) {
    next if ($st->{rank} // '') eq 'deprecated';
    my $dv = $st->{mainsnak}{datavalue} // next;
    my $v  = $dv->{value} // next;
    push @out, $v->{id} if ref($v) eq 'HASH' && $v->{id};
  }
  return @out;
}

sub times_for {
  my ($self, $prop) = @_;
  my @out;
  for my $st (@{ $self->_claims($prop) }) {
    next if ($st->{rank} // '') eq 'deprecated';
    my $dv = $st->{mainsnak}{datavalue} // next;
    my $v  = $dv->{value} // next;
    push @out, $v->{time} if ref($v) eq 'HASH' && $v->{time};
  }
  return @out;
}

# ----------------------------
# Labels / sitelinks
# ----------------------------
sub label_en {
  my ($self) = @_;
  my $ent = $self->entity // return undef;
  return $ent->{labels}{'en-gb'}{value}
      // $ent->{labels}{'en'}{value}
      // undef;
}

sub enwiki_url {
  my ($self) = @_;
  my $ent = $self->entity // return undef;
  my $links = $ent->{sitelinks} // {};
  return undef unless $links->{enwiki};
  my $title = $links->{enwiki}{title} // return undef;
  $title =~ s/ /_/g;
  return "https://en.wikipedia.org/wiki/$title";
}

# ----------------------------
# Dates / sex
# ----------------------------
sub birth_time { my ($self) = @_; my ($t) = $self->times_for('P569'); return $t }
sub death_time { my ($self) = @_; my ($t) = $self->times_for('P570'); return $t }

sub _wd_date_str {
  my ($t) = @_;
  return unless defined $t && $t =~ /^\+?(\d{4})(?:-(\d{2})-(\d{2}))?/;
  my ($y,$m,$d) = ($1, $2 // "01", $3 // "01");
  return sprintf "%04d-%02d-%02d", $y, $m, $d;
}

sub birth_date { my ($self) = @_; return _wd_date_str($self->birth_time) }
sub death_date { my ($self) = @_; return _wd_date_str($self->death_time) }

sub sex {
  my ($self) = @_;
  for my $st (@{ $self->_claims('P21') }) {
    my $v = $st->{mainsnak}{datavalue}{value};
    next unless ref($v) eq 'HASH' && $v->{id};
    return 'm' if $v->{id} eq 'Q6581097';
    return 'f' if $v->{id} eq 'Q6581072';
  }
  return undef;
}

# ----------------------------
# Parents / children
# ----------------------------
sub parent_qids {
  my ($self) = @_;
  my %seen;
  my @ids = ($self->ids_for('P22'), $self->ids_for('P25'));
  return grep { $_ && !$seen{$_}++ } @ids;
}

sub child_qids_all { my ($self) = @_; return $self->ids_for('P40') }

# P40 where ANY P1039 (type of kinship) is present (e.g., foster/step/adopted)
sub child_qids_nonbio {
  my ($self) = @_;
  my @out;
  for my $st (@{ $self->_claims('P40') }) {
    next if ($st->{rank} // '') eq 'deprecated';
    my $dv  = $st->{mainsnak}{datavalue} // next;
    my $v   = $dv->{value} // next;
    my $qid = (ref($v) eq 'HASH') ? $v->{id} : undef;
    next unless $qid;
    my $q = $st->{qualifiers} // {};
    push @out, $qid if $q->{'P1039'} && @{$q->{'P1039'}};
  }
  return @out;
}

# P40 where NO P1039 kinship qualifier exists (treat as biological/adoptive)
sub child_qids_biological {
  my ($self) = @_;
  my @out;
  for my $st (@{ $self->_claims('P40') }) {
    next if ($st->{rank} // '') eq 'deprecated';
    my $dv  = $st->{mainsnak}{datavalue} // next;
    my $v   = $dv->{value} // next;
    my $qid = (ref($v) eq 'HASH') ? $v->{id} : undef;
    next unless $qid;
    my $q = $st->{qualifiers} // {};
    next if $q->{'P1039'} && @{$q->{'P1039'}};  # non-bio → skip
    push @out, $qid;
  }
  return @out;
}

# True if THIS entity is a P22/P25 parent of $child (another Entity object)
sub is_parent_of {
  my ($self, $child) = @_;
  my $me = $self->qid // return 0;
  return 0 unless $child && $child->can('parent_qids');
  my %p = map { $_ => 1 } $child->parent_qids;
  return $p{$me} ? 1 : 0;
}

# ----------------------------
# Media
# ----------------------------
sub image_filename {
  my ($self) = @_;
  for my $st (@{ $self->_claims('P18') }) {
    my $dv = $st->{mainsnak}{datavalue} // next;
    my $v  = $dv->{value};
    return $v if defined $v && !ref($v); # commonsMedia string
  }
  return undef;
}

# ------------------------------------------------------------------
# Convenience one-argument constructor
# Usage: my $wd = Succession::WikiData::Entity::from_qid('Q123');
# ------------------------------------------------------------------
sub from_qid ($qid) {
  die "from_qid() requires a QID like Q12345" unless defined $qid && $qid =~ /^Q\d+$/;
  return __PACKAGE__->new(qid => $qid);
}

1;

