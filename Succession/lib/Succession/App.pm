package Succession::App;

use Moose;
use Moose::Util::TypeConstraints;
use experimental 'signatures'; # After Moose because Moose turns all warnings on
use DateTime;
use DateTime::Format::Strptime;
use Lingua::EN::Numbers 'num2en';
use XML::Feed;
use URI;
use Sys::Hostname;

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

#sub BUILD( $self, @ ) {
#  die 'Date cannot be before ' . $self->earliest->strftime('%d %B %Y')
#    if $self->too_early;
#
#  die 'Date cannot be after today' if $self->too_late;
#}

has request => (
  is => 'ro',
  isa => 'Succession::Request',
  lazy_build => 1,
);


sub _build_request(@) {
  die "No request attribute given to " . __PACKAGE__;
}

has host => (
  is => 'ro',
  isa => 'Str',
  lazy_build => 1,
);

sub _build_host($self) {
  return $self->request->uri_base;
}

has model => (
  is => 'ro',
  isa => 'Succession::Model',
  lazy_build => 1,
  handles => [ qw( get_succession get_succession_data interesting_dates ) ],
);

sub _build_model(@) {
  return Succession::Model->new;
}

has today => (
  is => 'ro',
  isa => 'SuccessionDate',
  lazy_build => 1,
  coerce => 1,
);

sub _build_today(@) {
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

sub _build_list_size_str( $self ) {
  return num2en($self->list_size);
}

has sovereign => (
  is => 'ro',
  isa => 'Succession::Schema::Result::Sovereign',
  lazy_build => 1,
);

sub _build_sovereign( $self ) {
  return $self->model->sovereign_on_date($self->request->date);
}

has sovereign_duration => (
  is => 'ro',
  isa => 'DateTime::Duration',
  lazy_build => 1,
);

sub _build_sovereign_duration( $self ) {
  return $self->request->date - $self->sovereign->start;
}

has succession => (
  is => 'ro',
  isa => 'ArrayRef',
  lazy_build => 1,
);

sub _build_succession( $self ) {
  my $succ = [
    $self->model->succession_on_date($self->request->date)->succession_people->all
  ];

  my @short_succ = grep {
    ! $_->excluded_on_date($self->request->date);
  } @$succ;

  $#short_succ = $self->list_size - 1 if $#short_succ >= $self->list_size;

  return \@short_succ;
}

has feed => (
  is => 'ro',
  isa => 'Maybe[XML::Feed]',
  lazy_build => 1,
);

sub _build_feed($) {
  return XML::Feed->parse(
    URI->new('https://blog.lineofsuccession.co.uk/feed')
  );
}

has title => (
  is => 'ro',
  isa => 'Str',
  lazy_build => 1,
);

sub _build_title( $self ) {
  my $path = $self->request->path;

  my $title = 'British Line of Succession';

  if ($self->request->is_home_page) {
    return $title . ' on any date in the last 200 years.';
  }

  if ($self->request->is_date_page) {
    return $title . ' on ' . $self->request->date->strftime('%e %B %Y');
  }

  if ($self->request->is_person_page) {
    return $self->request->person->name . ' (' . $self->request->person->years . ") - $title";
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

sub _build_description( $self ) {
  my $path = $self->request->path;

  my $desc = 'See the Line of Succession to the British Throne';

  if ($path eq '/') {
    return $desc . ' on any date in the last 200 years.';
  }

  if ($path =~ m[^/\d\d\d\d\-\d\d\-\d\d]) {
    return $desc . ' on ' . $self->request->date->strftime('%e %B %Y') . '.';
  }

  if ($path =~ m[^/p/]) {
    return 'Details of ' . $self->request->person->name .
           ' (' . $self->request->person->years . ')' .
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

sub _build_static_titles($) {
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
    anniversaries => {
      title => 'List of Upcoming Anniversaries and Birthdays in the British Line of Succession',
      desc  => 'List of Upcoming Anniversaries and Birthdays in the British Line of Succession',
    },
  };
}

sub image( $self ) {
  if ($self->request->is_home_page or $self->request->is_date_page) {
    return $self->sovereign->image . '.jpg';
  } else {
    return 'Imperial_State_Crown.png';
  }
}

sub too_early( $self ) {
  return $self->request->date < $self->earliest;
}

sub too_late( $self ) {
  return DateTime->now < $self->request->date;
}

sub is_valid_date( $self, $date ) {
  return !! DateTime::Format::Strptime->new(
    pattern => '%Y-%m-%d'
  )->parse_datetime($date);
}

sub canonical( $self ) {
  if ($self->request->is_date_page) {
    return '/' . $self->canonical_date;
  } else {
    return $self->request->path;
  }
}

sub canonical_date( $self ) {
  return $self->model->get_canonical_date($self->request->date);
}

sub alternate( $self ) {
  if ($self->request->is_date_page) {
    return '/' . $self->page_date;
  } else {
    return $self->request->path;
  }
}

sub page_date( $self ) {
  return '' unless $self->request->date;
  return '' if $self->request->date == $self->today;
  return $self->request->date->strftime('%Y-%m-%d');
}

sub prev_change_date( $self ) {
  my $date = $self->model->get_prev_change_date($self->request->date);
  return $date ? $date->change_date : '';
}

sub next_change_date( $self ) {
  my $date = $self->model->get_next_change_date($self->request->date);
  return $date ? $date->change_date : '';
}

sub prev_day( $self ) {
  my $date = $self->request->date;

  return unless $self->request->is_home_page or $self->request->is_date_page;

  if ($date > $self->earliest) {
    return $date->clone->subtract(days => 1);
  }

  return;
}

sub next_day( $self ) {
  my $date = $self->request->date;

  return unless $self->request->is_home_page or $self->request->is_date_page;

  if ($date < $self->today) {
    return $date->clone->add(days => 1);
  }

  return;
}

sub get_changes( $self ) {
  return $self->model->get_changes_on_date($self->request->date);
}

sub error( $self ) {
  if ($self->request->is_date_page) {
    if ($self->too_early) {
      return 'Date cannot be before ' . $self->earliest->strftime('%d %B %Y');
    }

    if ($self->too_late) {
      return 'Date cannot be after today';
    }
  }

  if ($self->request->is_person_page) {
    unless ($self->request->person) {
      return "'" . ($self->request->path =~ m[^/p/(.*)] ? $1 : '') . "' is not a valid person identifier";
    }
  }

  return;
}

sub json_ld_type($) {
  return 'ItemList';
}

sub json_ld_fields($) {
  return [];
}

around json_ld_data => sub {
  my $orig = shift;
  my $self = shift;

  my $data = $self->$orig(@_);

  if ($self->request->person) {
    $data = $self->request->person->json_ld_data;
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

sub make_succ_str_for_date( $self, $date = undef) {
  $date //= $self->request->date;

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
