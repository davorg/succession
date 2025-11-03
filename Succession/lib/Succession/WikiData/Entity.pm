package Succession::WikiData::Entity;
use v5.40;
use feature qw(class try);
no warnings qw(experimental::class experimental::try);
use utf8;

use HTTP::Tiny;
use JSON::MaybeXS ();

class Succession::WikiData::Entity {

  # ---------- fields ----------
  field $qid             :param;   # final QID (may change after redirects)
  field $data;                      # full decoded JSON payload
  field $entity;                    # entity hashref for $qid
  field $redirected_from;           # original QID if redirect happened

  field $http = HTTP::Tiny->new(
    agent        => "Succession-WikiData-Entity/0.03",
    timeout      => 20,
    max_redirect => 3,
  );
  field $json = JSON::MaybeXS->new(utf8 => 1);

  # Build step: fetch & follow redirects once constructed
  ADJUST {
    $self->_fetch_and_follow_redirects();
  }

  # ---------- basic accessors ----------
  method qid             { $qid }
  method data            { $data }
  method entity          { $entity }
  method redirected_from { $redirected_from }

  # ---------- fetch with redirect handling ----------
  method _fetch_and_follow_redirects () {
    my $hops    = 0;
    my $current = $qid;
    my $from;

    while ($hops++ < 3) {
      my $url = "https://www.wikidata.org/wiki/Special:EntityData/$current.json";

      my $res;
      try {
        $res = $http->get($url);
      } catch ($e) {
        die "HTTP error fetching $url: $e";
      };

      die "HTTP $res->{status} $res->{reason} for $url" unless $res->{success};

      my $doc;
      try {
        $doc = $json->decode($res->{content});
      } catch ($e) {
        die "JSON decode failed for $current: $e";
      };

      $data = $doc;  # keep last raw document

      # Top-level redirects map
      if ($doc->{redirects} && $doc->{redirects}{$current} && $doc->{redirects}{$current}{to}) {
        $from //= $current;
        $current = $doc->{redirects}{$current}{to};
        next;
      }

      # Normal case: entities->{$current}
      if ($doc->{entities} && $doc->{entities}{$current}) {
        $qid             = $current;
        $redirected_from = $from if defined $from && $from ne $current;
        $entity          = $doc->{entities}{$current};
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

    die "Exceeded redirect hops while fetching $qid";
  }

  # ---------- generic claim readers ----------
  method _claims ($prop) {
    return ($entity->{claims}{$prop} // []);
  }

  method ids_for ($prop) {
    my @out;
    for my $st (@{ $self->_claims($prop) }) {
      next if ($st->{rank} // '') eq 'deprecated';
      my $dv = $st->{mainsnak}{datavalue} // next;
      my $v  = $dv->{value} // next;
      push @out, $v->{id} if ref($v) eq 'HASH' && $v->{id};
    }
    return @out;
  }

  method times_for ($prop) {
    my @out;
    for my $st (@{ $self->_claims($prop) }) {
      next if ($st->{rank} // '') eq 'deprecated';
      my $dv = $st->{mainsnak}{datavalue} // next;
      my $v  = $dv->{value} // next;
      push @out, $v->{time} if ref($v) eq 'HASH' && $v->{time};
    }
    return @out;
  }

  # ---------- labels / sitelinks ----------
  method label_en () {
    return $entity->{labels}{'en-gb'}{value}
        // $entity->{labels}{'en'}{value}
        // undef;
  }

  method enwiki_url () {
    my $links = $entity->{sitelinks} // {};
    return undef unless $links->{enwiki};
    my $title = $links->{enwiki}{title} // return undef;
    $title =~ s/ /_/g;
    return "https://en.wikipedia.org/wiki/$title";
  }

  # ---------- dates / sex ----------
  method birth_time ()  { ($self->times_for('P569'))[0] }
  method death_time ()  { ($self->times_for('P570'))[0] }

  method _wd_date_str ($t) {
    return unless defined $t && $t =~ /^\+?(\d{4})(?:-(\d{2})-(\d{2}))?/;
    my ($y,$m,$d) = ($1, $2 // "01", $3 // "01");
    return sprintf "%04d-%02d-%02d", $y, $m, $d;
  }

  method birth_date () { $self->_wd_date_str($self->birth_time) }
  method death_date () { $self->_wd_date_str($self->death_time // undef) }

  method sex () {
    for my $st (@{ $self->_claims('P21') }) {
      my $v = $st->{mainsnak}{datavalue}{value};
      next unless ref($v) eq 'HASH' && $v->{id};
      return 'm' if $v->{id} eq 'Q6581097';
      return 'f' if $v->{id} eq 'Q6581072';
    }
    return undef;
  }

  # ---------- parents / children ----------
  method parent_qids () {
    my %seen;
    my @ids = ($self->ids_for('P22'), $self->ids_for('P25'));
    return grep { $_ && !$seen{$_}++ } @ids;
  }

  method child_qids_all () { $self->ids_for('P40') }

  # P40 where ANY P1039 (type of kinship) is present (e.g., foster/step/adopted)
  method child_qids_nonbio () {
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
  method child_qids_biological () {
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
  method is_parent_of ($child) {
    my $me = $qid // return 0;
    return 0 unless $child && $child->can('parent_qids');
    my %p = map { $_ => 1 } $child->parent_qids;
    return $p{$me} ? 1 : 0;
  }

  # ---------- media ----------
  method image_filename () {
    for my $st (@{ $self->_claims('P18') }) {
      my $dv = $st->{mainsnak}{datavalue} // next;
      my $v  = $dv->{value};
      return $v if defined $v && !ref($v); # commonsMedia string
    }
    return undef;
  }
}

# ------------------------------------------------------------------
# Convenience one-argument constructor (no invocant marker required)
# Usage: my $wd = Succession::WikiData::Entity::from_qid('Q123');
# ------------------------------------------------------------------
sub from_qid ($qid) {
  die "from_qid() requires a QID like Q12345" unless defined $qid && $qid =~ /^Q\d+$/;
  return __PACKAGE__->new(qid => $qid);
}

1;
