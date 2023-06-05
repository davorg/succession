package Succession::App;

use strict;
use warnings;

use Moose;
use Moose::Util::TypeConstraints;
use DateTime;
use DateTime::Format::Strptime;
use Lingua::EN::Numbers 'num2en';
use XML::Feed;
use URI;

use Succession::Model;
with 'MooX::Role::JSON_LD';

use feature 'say';

subtype 'SuccessionDate',
as 'DateTime';

coerce 'SuccessionDate',
from 'Str',
via {
  DateTime::Format::Strptime->new(pattern => '%Y-%m-%d')->parse_datetime($_);
};

sub BUILD {
  my $self = shift;

  die 'Date cannot be before ' . $self->earliest->strftime('%d %B %Y')
    if $self->too_early;

  die 'Date cannot be after today' if $self->too_late;
}

has request => (
  is => 'ro',
  isa => 'Dancer2::Core::Request',
  lazy_build => 1,
);


sub _build_request {
  die "No request attribute given to " . __PACKAGE__;
}

has model => (
  is => 'ro',
  isa => 'Succession::Model',
  lazy_build => 1,
  handles => [ qw( get_succession get_succession_data interesting_dates ) ],
);

sub _build_model {
  return Succession::Model->new;
}

has date => (
  is => 'ro',
  isa => 'SuccessionDate',
  lazy_build =>  1,
  coerce => 1,
);

sub _build_date {
  return DateTime->today;
}

has today => (
  is => 'ro',
  isa => 'SuccessionDate',
  lazy_build => 1,
  coerce => 1,
);

sub _build_today {
  return DateTime->today;
}

has earliest => (
  is => 'ro',
  isa => 'DateTime',
  required => 1,
  default => sub { DateTime::Format::Strptime->new(
    pattern => '%Y-%m-%d'
  )->parse_datetime('1820-01-29') },
);

has list_size => (
  is => 'ro',
  isa => 'Int',
  required => 1,
  default => 30,
);

has list_size_str => (
  is => 'ro',
  isa => 'Str',
  required => 1,
  lazy_build => 1,
);

sub _build_list_size_str {
  my $self = shift;
  return num2en($self->list_size);
}

has sovereign => (
  is => 'ro',
  isa => 'Succession::Schema::Result::Sovereign',
  lazy_build => 1,
);

sub _build_sovereign {
  my $self = shift;
  return $self->model->sovereign_on_date($self->date);
}

has sovereign_duration => (
  is => 'ro',
  isa => 'DateTime::Duration',
  lazy_build => 1,
);

sub _build_sovereign_duration {
  my $self = shift;
  return $self->date - $self->sovereign->start;
}

has succession => (
  is => 'ro',
  isa => 'ArrayRef',
  lazy_build => 1,
);

sub _build_succession {
  my $self = shift;
  my $succ = $self->model->succession_on_date($self->date);

  my @short_succ = grep {
    ! $_->excluded_on_date($self->date);
  } @$succ;

  $#short_succ = $self->list_size - 1 if $#short_succ >= $self->list_size;

  return \@short_succ;
}

has person => (
  is => 'rw',
  isa => 'Maybe[Succession::Schema::Result::Person]',
);

has feed => (
  is => 'ro',
  isa => 'Maybe[XML::Feed]',
  lazy_build => 1,
);

sub _build_feed {
  return XML::Feed->parse(
    URI->new('https://blog.lineofsuccession.co.uk/feed/')
  );
}

has title => (
  is => 'ro',
  isa => 'Str',
  lazy_build => 1,
);

sub _build_title {
  my $self = shift;

  my $path = $self->request->path;

  my $title = 'British Line of Succession';

  if ($path eq '/') {
    return $title . ' on any date in the last 200 years.';
  }

  if ($path =~ m[^/\d\d\d\d\-\d\d\-\d\d]) {
    return $title . ' on ' . $self->date->strftime('%e %B %Y');
  }

  if ($path =~ m[^/p/]) {
    return $self->person->name . ' (' . $self->person->years . ") - $title";
  }

  for (keys %{ $self->static_titles }) {
    if ($path =~ m[^/$_\b]) {
      return $self->static_titles->{$_}{title};
    }
  }

  return $title;
}

has description => (
  is => 'ro',
  isa => 'Str',
  lazy_build => 1,
);

sub _build_description {
  my $self = shift;

  my $path = $self->request->path;

  my $desc = 'See the Line of Succession to the British Throne';

  if ($path eq '/') {
    return $desc . ' on any date in the last 200 years.';
  }

  if ($path =~ m[^/\d\d\d\d\-\d\d\-\d\d]) {
    return $desc . ' on ' . $self->date->strftime('%e %B %Y') . '.';
  }

  if ($path =~ m[^/p/]) {
    return 'Details of ' . $self->person->name .
           ' (' . $self->person->years . ')' .
           ' in the Line of Succession to the British Throne.';
  }

  for (keys %{ $self->static_titles }) {
    if ($path =~ m[^/$_\b]) {
      return $self->static_titles->{$_}{desc};
    }
  }

  return $desc;
}

has static_titles => (
  is => 'ro',
  isa => 'HashRef',
  lazy_build => 1,
);

sub _build_static_titles {
  return {
    changes => {
      title => 'Timeline of Changes to the British Line of Succession',
      desc  => 'Timeline of Changes to the British Line of Succession',
    },
    dates   => {
      title => 'Browse interesting dates for the British Line of Succession',
      desc  => 'Browse interesting dates for the British Line of Succession',
    },
    shop   => {
      title => 'British Line of Succession Shop',
      desc  => 'British Line of Succession Shop',
    },
  };
}

sub image {
  my $self = shift;

  if ($self->is_home_page or $self->is_date_page) {
    return $self->sovereign->image;
  } else {
    return 'Imperial_State_Crown.png';
  }
}

sub is_date_page {
  my $self = shift;

  return $self->request->path =~ m[^/\d\d\d\d-\d\d-\d\d];
}

sub is_home_page {
  my $self = shift;

  return $self->request->path eq '/';
}

sub too_early {
  my $self = shift;
  return $self->date < $self->earliest;
}

sub too_late {
  my $self = shift;
  return DateTime->now < $self->date;
}

sub is_valid_date {
  my $self = shift;

  return !! DateTime::Format::Strptime->new(
    pattern => '%Y-%m-%d'
  )->parse_datetime($_[0]);
}

sub canonical {
  my $self = shift;

  if ($self->is_date_page) {
    return '/' . $self->canonical_date;
  } else {
    return $self->request->path;
  }
}

sub canonical_date {
  return $_[0]->model->get_canonical_date($_[0]->date);
}

sub alternate {
  my $self = shift;

  if ($self->is_date_page) {
    return '/' . $self->page_date;
  } else {
    return $self->request->path;
  }
}

sub page_date {
  my $self = shift;

  return '' unless $self->date;
  return '' if $self->date == $self->today;
  return $self->date->strftime('%Y-%m-%d');
}

sub prev_change_date {
  my $self = shift;
  my $date = $self->model->get_prev_change_date($self->date);
  return $date ? $date->change_date : '';
}

sub next_change_date {
  my $self = shift;
  my $date = $self->model->get_next_change_date($self->date);
  return $date ? $date->change_date : '';
}

sub prev_day {
  my $self = shift;
  my $date = $self->date;

  return unless $self->is_home_page or $self->is_date_page;

  if ($date > $self->earliest) {
    return $date->clone->subtract(days => 1);
  }

  return;
}

sub next_day {
  my $self = shift;
  my $date = $self->date;

  return unless $self->is_home_page or $self->is_date_page;

  if ($date < $self->today) {
    return $date->clone->add(days => 1);
  }

  return;
}

sub get_changes {
  my $self = shift;
  return $self->model->get_changes_on_date($self->date);
}

sub json_ld_type {
  return 'ItemList';
}

sub json_ld_fields {
  return [];
}

around json_ld_data => sub {
  my $orig = shift;
  my $self = shift;

  my $data = $self->$orig(@_);

  if ($self->person) {
    $data = $self->person->json_ld_data;
  } else {
    my $pos = 1;

    my $people;
    for ($self->sovereign->person, @{$self->succession}) {
      my $d = $_->json_ld_data;
      delete $d->{'@context'};

      push @$people, {
        '@type'  => 'ListItem',
        position => $pos++,
        item     => $d,
      };
    }

    $data->{itemListElement} = $people;
  }

  return $data;
};

sub make_succ_str_for_date {
  my $self = shift;
  my ($date) = @_;

  $date //= $self->date;

  my @succ = @{ $self->model->succession_on_date($date) };

  $#succ = $self->list_size - 1 if @succ > $self->list_size;

  return join ':', map {
    $_->excluded_on_date($date) ? $_->id . 'x' : $_->id
  } @succ;
}

around BUILDARGS => sub {
  my $orig  = shift;
  my $class = shift;

  if ( @_ == 1 && !ref $_[0] ) {
    return $class->$orig({ date => $_[0] });
  }

  if (not @_ or (@_ == 1 and not defined $_[0])) {
    return $class->$orig({ date => DateTime->today });
  }

  return $class->$orig(@_);
};

no Moose;
__PACKAGE__->meta->make_immutable;

1;
