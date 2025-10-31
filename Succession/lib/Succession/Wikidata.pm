package Succession::Wikidata;
use strict;
use warnings;
use utf8;

require Exporter;
our @ISA       = qw[Exporter];
our @EXPORT_OK = qw[get_media_for_qid get_short_bio];

use JSON::MaybeXS;
use HTTP::Tiny;
use URI::Escape qw(uri_escape_utf8);
use List::Util qw(first);

my $JSON = JSON::MaybeXS->new(utf8 => 1);
my $HTTP = HTTP::Tiny->new(
  agent   => "LineOfSuccession/1.0",
  timeout => 20,
);

# Fetch one entity JSON (full)
sub _entity {
  my ($qid) = @_;
  return unless $qid && $qid =~ /^Q\d+$/;
  my $url = "https://www.wikidata.org/wiki/Special:EntityData/$qid.json";
  my $res = $HTTP->get($url);
  return unless $res->{success};
  my $data = eval { $JSON->decode($res->{content}) } || return;
  return $data->{entities}{$qid};
}

# Extract a (possibly language-qualified) qualifier value for a statement
sub _qual_lang_value {
  my ($st, $prop, $langs) = @_;
  my $quals = $st->{qualifiers} || {};
  my $arr   = $quals->{$prop} || [];
  for my $q (@$arr) {
    my $dv = $q->{datavalue} || {};
    my $v  = $dv->{value};
    next unless ref $v eq 'HASH';
    if (exists $v->{text}) {         # monolingual text value
      for my $lang (@$langs) {
        return $v->{text} if ($v->{language}||'') eq $lang;
      }
    }
  }
  return;
}

# replace _first_file_title with this:
sub _pick_commons_file {
  my ($entity, $prop) = @_;
  my $claims = $entity->{claims} || {};
  my $arr    = $claims->{$prop} || [];
  my @candidates;

  for my $st (@$arr) {
    next if ($st->{rank}||'') eq 'deprecated';

    my $dv = $st->{mainsnak}{datavalue};
    next unless $dv && $dv->{type} && $dv->{type} eq 'string';  # commonsMedia -> string
    my $file = $dv->{value} // next;
    next unless $file ne '';

    # grab an optional P585 (point in time) to sort by recency
    my $p585_time;
    if (my $quals = $st->{qualifiers}) {
      if (my $pt = $quals->{P585} && $quals->{P585}[0]{datavalue}{value}{time}) {
        $p585_time = $pt; # "+YYYY-MM-DDT.."
      }
    }

    push @candidates, {
      file      => $file,
      stmt      => $st,
      rank      => ($st->{rank} // 'normal'),
      p585_time => ($p585_time // ''), # empty sorts lowest
    };
  }

  return unless @candidates;

  # rank: preferred > normal
  my %rank_w = ( preferred => 2, normal => 1 );
  @candidates = sort {
       ($rank_w{$b->{rank}} // 0) <=> ($rank_w{$a->{rank}} // 0)
    || ($b->{p585_time} cmp $a->{p585_time}) # lex sort works on +YYYY...
  } @candidates;

  my $best = $candidates[0];
  return ($best->{file}, $best->{stmt});
}

sub _thumb_url {
  my ($file_title, $width) = @_;
  return unless $file_title;
  (my $name = $file_title) =~ s/^File://i;
  $name =~ s/ /_/g;
  my $enc = uri_escape_utf8($name);
  return "https://commons.wikimedia.org/wiki/Special:FilePath/$enc?width=$width";
}

sub _file_page {
  my ($file_title) = @_;
  return unless $file_title;
  (my $name = $file_title) =~ s/^File://i;
  $name =~ s/ /_/g;
  my $enc = uri_escape_utf8($name);
  return "https://commons.wikimedia.org/wiki/File:$enc";
}

sub get_media_for_qid {
  my ($qid, %opts) = @_;
  my $width = $opts{width} || 600;
  my $entity = _entity($qid) or return {};

  my %out;
  # short description
  if (my $desc = $entity->{descriptions}) {
    $out{short_desc} = $desc->{en}->{value} // $desc->{'en-gb'}->{value};
  }

  # Primary image (P18), with caption via P2096 qualifier if present
  if (my ($file, $st) = _pick_commons_file($entity, 'P18')) {
    $out{image_url}  = _thumb_url($file, $width);
    $out{image_page} = _file_page($file);
    my $cap = _qual_lang_value($st, 'P2096', [qw(en-gb en)]);
    $out{caption} = $cap if defined $cap && $cap ne '';
  }

  # Fallbacks if no P18
  if (!$out{image_url}) {
    if (my ($coat) = _pick_commons_file($entity, 'P94')) {
      $out{coat_of_arms} = {
        url  => _thumb_url($coat, $width),
        page => _file_page($coat),
      };
    }
    if (my ($sig) = _pick_commons_file($entity, 'P109')) {
      $out{signature} = {
        url  => _thumb_url($sig, $width),
        page => _file_page($sig),
      };
    }
  }

  return \%out;
}

sub _enwiki_title_from_entity {
  my ($entity) = @_;
  my $links = $entity->{sitelinks} || {};
  return $links->{enwiki} ? $links->{enwiki}{title} : undef;
}

sub _wikipedia_title_from_url {
  my ($url) = @_;
  return unless $url && $url =~ m{https?://en\.wikipedia\.org/wiki/([^#?]+)};
  my $t = $1; $t =~ s/_/ /g;
  return $t;
}

# Fetch Wikipedia REST summary (clean, first paragraph style)
sub _fetch_wikipedia_summary {
  my ($title) = @_;
  return unless $title;
  my $path  = $title; $path =~ s/ /_/g;
  my $url   = "https://en.wikipedia.org/api/rest_v1/page/summary/$path";
  my $res   = $HTTP->get($url);
  return unless $res->{success};

  my $data  = eval { $JSON->decode($res->{content}) } || return;
  return if ($data->{type} && $data->{type} eq 'disambiguation');

  my $text = $data->{extract} // $data->{description};   # prefer extract
  return unless $text && $text ne '';

  # Trim to a sensible length if caller asks later; we return full summary here
  return {
    text  => $text,
    url   => ($data->{content_urls}{desktop}{page} // "https://en.wikipedia.org/wiki/$path"),
    title => $data->{title} // $title,
  };
}

# Public: best-effort short bio
# Usage:
#   get_short_bio(qid => 'Q43274', wikipedia_url => $person->wikipedia, max_chars => 360)
sub get_short_bio {
  my (%args) = @_;
  my $qid          = $args{qid};
  my $wikipedia    = $args{wikipedia_url};
  my $max_chars    = $args{max_chars} // 360;      # approx two lines
  my $prefer_wiki  = $args{prefer_wikipedia} // 1; # try wiki first

  my $entity;
  my $title = $wikipedia ? _wikipedia_title_from_url($wikipedia) : undef;

  if (!$title && $qid) {
    $entity = _entity($qid) or return {};
    $title  = _enwiki_title_from_entity($entity);
  }

  # 1) Wikipedia summary (if we have a title or URL)
  if ($prefer_wiki && $title) {
    if (my $sum = _fetch_wikipedia_summary($title)) {
      my $t = _truncate($sum->{text}, $max_chars);
      return { text => $t, source => 'wikipedia', url => $sum->{url} };
    }
  }

  # 2) Fallback: Wikidata description (en or en-gb)
  if (!$entity && $qid) {
    $entity = _entity($qid) or return {};
  }
  if ($entity && $entity->{descriptions}) {
    my $desc = $entity->{descriptions}{'en-gb'}{value}
            || $entity->{descriptions}{'en'}{value};
    if ($desc) {
      my $t = _truncate($desc, $max_chars);
      my $url = $title ? "https://en.wikipedia.org/wiki/" . ($title =~ s/ /_/gr)
                       : "https://www.wikidata.org/wiki/$qid";
      return { text => $t, source => 'wikidata', url => $url };
    }
  }

  return {};
}

sub _truncate {
  my ($s, $limit) = @_;
  return $s unless defined $s && length($s) > $limit;
  # cut at a word boundary if possible
  my $cut = substr($s, 0, $limit);
  $cut =~ s/\s+\S*$//; # backtrack to last space
  return $cut . "…";
}



1;

