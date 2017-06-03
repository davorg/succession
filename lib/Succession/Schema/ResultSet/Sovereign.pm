package Succession::Schema::ResultSet::Sovereign;

use Moose;
use MooseX::NonMoose;

extends 'DBIx::Class::ResultSet';

sub BUILDARGS { $_[2] }

sub sovereign_on_date {
  my $self = shift;
  my ($date) = @_;

  $date = $self->result_source->schema->storage->
          datetime_parser->format_datetime($date);

  return $self->find({
    start => { '<=' => $date },
    end   => [ { '>=' => $date }, undef ],
  });
}

__PACKAGE__->meta->make_immutable;

1;
