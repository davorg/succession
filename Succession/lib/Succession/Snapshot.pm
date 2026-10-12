package Succession::Snapshot;

use v5.32;
use strict;
use warnings;

# Build dated lists from one in-memory copy of the genealogy. Ranked entries
# remain eligible-only; display entries also retain exclusions before the cutoff.
sub new {
  my ($class, %args) = @_;
  my $schema = $args{schema} or die "schema is required\n";
  my $self = bless {
    schema   => $schema,
    earliest => $args{earliest} // '1820-01-29',
    limit    => $args{limit} // 30,
    people   => {},
    children => {},
    order    => {},
  }, $class;
  die "limit must be a positive integer\n" unless $self->{limit} =~ /\A[1-9][0-9]*\z/;

  for my $person ($schema->resultset('Person')->search(undef, {
    prefetch => 'exclusions',
  })->all) {
    my %p = $person->get_columns;
    $p{exclusions} = [ map { { $_->get_columns } } $person->exclusions ];
    $self->{people}{$p{id}} = \%p;
    push @{ $self->{children}{$p{parent}} }, $p{id} if defined $p{parent};
  }
  my $people = $self->{people};
  for my $id (keys %$people) {
    my %seen;
    my $ancestor = $id;
    while (defined $ancestor) {
      die "Cycle in genealogy at person $ancestor\n" if $seen{$ancestor}++;
      my $p = $people->{$ancestor} or die "Missing parent $ancestor\n";
      die "Missing family_order for person $ancestor\n"
        if defined($p->{parent}) && !defined($p->{family_order});
      $ancestor = $p->{parent};
    }
  }
  for my $children (values %{ $self->{children} }) {
    @$children = sort {
      $people->{$a}{family_order} <=> $people->{$b}{family_order}
        || $people->{$a}{born} cmp $people->{$b}{born}
        || $a <=> $b
    } @$children;
  }
  $self->{sovereigns} = [ map { { $_->get_columns } }
    $schema->resultset('Sovereign')->search(undef, { order_by => 'start' })->all ];
  return $self;
}

sub _ordered_ids {
  my ($self, $root) = @_;
  return $self->{order}{$root} if $self->{order}{$root};
  my @ids;
  my $descend;
  $descend = sub {
    my ($parent) = @_;
    for my $child (@{ $self->{children}{$parent} // [] }) {
      push @ids, $child;
      $descend->($child);
    }
  };
  $descend->($root);
  my $ancestor = $root;
  while (defined(my $parent = $self->{people}{$ancestor}{parent})) {
    my $after = 0;
    for my $sibling (@{ $self->{children}{$parent} }) {
      if ($sibling == $ancestor) { $after = 1; next }
      next unless $after;
      push @ids, $sibling;
      $descend->($sibling);
    }
    $ancestor = $parent;
  }
  undef $descend; # release the recursive closure
  return $self->{order}{$root} = \@ids;
}

sub line_on_date {
  my ($self, $date, $limit) = @_;
  $date = $date->ymd if ref $date;
  $limit = $self->{limit} unless defined $limit;
  die "limit must be a positive integer\n" unless $limit =~ /\A[1-9][0-9]*\z/;
  die "date must be YYYY-MM-DD\n" unless $date =~ /\A[0-9]{4}-[0-9]{2}-[0-9]{2}\z/;
  my ($sovereign) = reverse grep {
    $_->{start} le $date && (!defined($_->{end}) || $date lt $_->{end})
  } @{ $self->{sovereigns} };
  die "No sovereign on $date\n" unless $sovereign;

  my (@rows, $rank);
  $rank = 0;
  for my $id (@{ $self->_ordered_ids($sovereign->{person_id}) }) {
    my $p = $self->{people}{$id};
    next if $p->{born} gt $date || (defined($p->{died}) && $p->{died} le $date);
    my ($exclusion) = grep {
      (!defined($_->{start}) || $_->{start} le $date)
        && (!defined($_->{end}) || $date lt $_->{end})
    } @{ $p->{exclusions} };
    push @rows, {
      person_id       => $id,
      display_order   => scalar(@rows) + 1,
      succession_rank => $exclusion ? undef : ++$rank,
      reason          => $exclusion ? $exclusion->{reason} : undef,
    };
    last if $rank >= $limit;
  }
  return \@rows;
}

sub full_line_on_date {
  my ($self, $date) = @_;
  return $self->line_on_date($date, scalar keys %{ $self->{people} });
}

sub _signature {
  return join ':', map {
    $_->{person_id} . (defined($_->{succession_rank}) ? '' : 'x' . ($_->{reason} // ''))
  } @{ $_[0] };
}

sub _events {
  my ($self, $date, $prev, $curr) = @_;
  my %before = map { $_->{person_id} => $_ } @$prev;
  my %after  = map { $_->{person_id} => $_ } @$curr;
  my @events;
  for my $s (@{ $self->{sovereigns} }) {
    push @events, [ $s->{person_id}, 'became sovereign', 'accession',
      $before{$s->{person_id}} ? $before{$s->{person_id}}{succession_rank} : undef ]
      if $s->{start} eq $date;
  }
  for my $id (sort { $a <=> $b } keys %{ $self->{people} }) {
    my $p = $self->{people}{$id};
    push @events, [ $id, 'was born', 'birth', $after{$id}{succession_rank} ]
      if $p->{born} eq $date && $after{$id};
    push @events, [ $id, 'died', 'death', $before{$id}{succession_rank} ]
      if defined($p->{died}) && $p->{died} eq $date && $before{$id};
    for my $x (@{ $p->{exclusions} }) {
      next unless $before{$id} || $after{$id};
      push @events, [ $id, 'was excluded', 'exclusion',
        $before{$id} ? $before{$id}{succession_rank} : undef ]
        if defined($x->{start}) && $x->{start} eq $date;
      push @events, [ $id, 'was unexcluded', 'unexclusion',
        $after{$id} ? $after{$id}{succession_rank} : undef ]
        if defined($x->{end}) && $x->{end} eq $date;
    }
  }
  return \@events;
}

sub plan {
  my ($self, $through) = @_;
  $through = $through->ymd if ref $through;
  my $schema = $self->{schema};
  my %existing = map { $_->get_column('from_date') => $_ }
    $schema->resultset('SuccessionPeriod')->all;
  my %dates = map { $_ => 1 } ($self->{earliest}, keys %existing);
  $dates{$_->get_column('change_date')} = 1 for $schema->resultset('ChangeDate')->all;
  for my $p (values %{ $self->{people} }) {
    $dates{$_} = 1 for grep { defined } $p->{born}, $p->{died};
    for my $x (@{ $p->{exclusions} }) {
      $dates{$_} = 1 for grep { defined } $x->{start}, $x->{end};
    }
  }
  for my $s (@{ $self->{sovereigns} }) {
    $dates{$_} = 1 for grep { defined } $s->{start}, $s->{end};
  }
  die "through date precedes existing periods\n" if grep { $_ gt $through } keys %existing;
  my (@plans, @differences, $prev);
  $prev = [];
  for my $date (sort grep { $_ ge $self->{earliest} && $_ le $through } keys %dates) {
    my $rows = $self->line_on_date($date);
    next if @plans && _signature($rows) eq _signature($prev);
    my @old = $existing{$date} ? $existing{$date}->succession_entries->search(undef, {
      order_by => 'rank',
    })->get_column('person_id')->all : ();
    my @new = map { $_->{person_id} } grep { defined $_->{succession_rank} } @$rows;
    push @differences, { date => $date, old => \@old, new => \@new }
      if $existing{$date} && join(':', @old) ne join(':', @new);
    push @plans, {
      date     => $date,
      existing => $existing{$date},
      rows     => $rows,
      events   => $self->_events($date, $prev, $rows),
    };
    $prev = $rows;
  }
  my %retained = map { $_->{date} => 1 } @plans;
  my @obsolete = sort grep { !$retained{$_} } keys %existing;
  return { periods => \@plans, differences => \@differences, obsolete => \@obsolete };
}

sub apply {
  my ($self, $plan) = @_;
  my $schema = $self->{schema};
  $schema->txn_do(sub {
    $schema->storage->dbh->do(q{
      CREATE TABLE IF NOT EXISTS succession_display_entry (
        period_id INTEGER NOT NULL REFERENCES succession_period(id),
        display_order INTEGER NOT NULL,
        person_id INTEGER NOT NULL REFERENCES person(id),
        succession_rank INTEGER,
        PRIMARY KEY (period_id, display_order),
        UNIQUE (period_id, person_id),
        UNIQUE (period_id, succession_rank)
      )
    });
    $schema->resultset('SuccessionDisplayEntry')->delete;
    $schema->resultset('SuccessionEntry')->delete;
    $schema->resultset('Change')->delete;
    if (@{ $plan->{obsolete} }) {
      $schema->resultset('SuccessionPeriod')->search({
        from_date => { -in => $plan->{obsolete} },
      })->delete;
      $schema->resultset('ChangeDate')->search({
        change_date => { -in => $plan->{obsolete} },
      })->delete;
    }
    my $periods = $plan->{periods};
    for my $i (0 .. $#$periods) {
      my $p = $periods->[$i];
      my $period = $p->{existing}
        // $schema->resultset('SuccessionPeriod')->create({ from_date => $p->{date} });
      $period->update({ to_date => $i < $#$periods ? $periods->[$i + 1]{date} : undef });
      my @display = map {
        +{ period_id => $period->id,
           person_id => $_->{person_id}, display_order => $_->{display_order},
           succession_rank => $_->{succession_rank} }
      } @{ $p->{rows} };
      $schema->resultset('SuccessionDisplayEntry')->populate(\@display) if @display;
      my @ranked = map {
        +{ period_id => $period->id, person_id => $_->{person_id}, rank => $_->{succession_rank} }
      } grep { defined $_->{succession_rank} } @{ $p->{rows} };
      $schema->resultset('SuccessionEntry')->populate(\@ranked) if @ranked;

      my $cd = $schema->resultset('ChangeDate')->find_or_create({ change_date => $p->{date} });
      $cd->update({ succession => join ':', map {
        $_->{person_id} . (defined($_->{succession_rank}) ? '' : 'x')
      } @{ $p->{rows} } });
      for my $event (@{ $p->{events} }) {
        $cd->changes->find_or_create({ person_id => $event->[0], description => $event->[1] });
      }
      my $events = $p->{events};
      my $type = !@$events ? ($i ? 'complex' : 'initial')
        : @$events == 1 ? $events->[0][2] : 'complex';
      my $person_id = @$events == 1 ? $events->[0][0] : undef;
      $period->update({ change_type => $type, person_id => $person_id,
        change_position => @$events == 1 ? $events->[0][3] : undef });
    }
    $schema->storage->dbh->do('ANALYZE');
  });
  return;
}

1;
