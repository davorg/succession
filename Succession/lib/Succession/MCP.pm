package Succession::MCP;

use Moo;

use DateTime;
use JSON::MaybeXS qw[encode_json];
use YAML::XS qw[LoadFile];

has server_version => (
  is => 'ro',
  required => 1,
);

has tools_file => (
  is => 'ro',
  required => 1,
);

has _tools => (
  is => 'lazy',
);

sub _build__tools {
  my ($self) = @_;
  return LoadFile($self->tools_file);
}

sub tool_docs {
  my ($self) = @_;

  return [
    map {
      +{
        $_->%*,
        input_schema_json => JSON::MaybeXS->new(pretty => 1)->encode($_->{inputSchema}),
      }
    } $self->_tools->@*
  ];
}

sub initialize_data {
  my ($self) = @_;

  return {
    protocolVersion => '2025-11-25',
    capabilities    => {
      tools => {},
    },
    serverInfo => {
      name    => 'line-of-succession',
      version => $self->server_version,
    },
  };
}

sub tools {
  my ($self) = @_;

  return [
    map {
      {
        name        => $_->{name},
        description => $_->{description},
        inputSchema => $_->{inputSchema},
      }
    } $self->_tools->@*
  ];
}

sub call_tool {
  my ($self, %args) = @_;
  my $params = $args{params};
  my $model  = $args{model};

  my $name = $params->{name} // '';
  my $tool_args = $params->{arguments} // {};

  return $self->tool_error("Unknown tool: $name")
    unless $name eq 'sovereign_on_date'
        || $name eq 'line_of_succession';

  my $date;

  if (exists $tool_args->{date}) {
    $date = $self->mcp_date($tool_args->{date});
    unless ($date) {
      return $self->tool_error('Invalid date format. Use YYYY-MM-DD.');
    }
  } else {
    $date = DateTime->today;
  }

  if ($name eq 'sovereign_on_date') {
    my $sov    = $model->sovereign_on_date($date);
    my $person = $sov->person;

    my $data = {
      date      => $date->ymd,
      sovereign => {
        name => $person->name,
        born => $person->born ? $person->born->ymd : undef,
        slug => $person->slug,
      },
    };

    my $text = "On " . $date->ymd . ", the sovereign was " . $person->name;

    return $self->tool_result($data, $text);
  }

  if ($name eq 'line_of_succession') {
    my $limit = $tool_args->{limit} // 10;
    $limit = 1  if $limit < 1;
    $limit = 30 if $limit > 30;

    my $data = $model->get_succession_data($date, $limit);

    my $text = "Line of succession on " . $date->ymd . ":\nSovereign: " .
               $data->{sovereign}->{name} . "\n" .
               join("\n", map { "$_->{number}. $_->{name}" } @{ $data->{successors} });

    return $self->tool_result($data, $text);
  }
}

sub mcp_date {
  my ($self, $date) = @_;
  return unless defined $date;
  return unless $date =~ /\A(\d{4})-(\d\d)-(\d\d)\z/;

  return eval {
    DateTime->new(
      year  => $1,
      month => $2,
      day   => $3,
    );
  };
}

sub tool_result {
  my ($self, $data, $text) = @_;

  $text //= encode_json($data);

  return {
    content => [{
      type => 'text',
      text => $text,
    }],
    structuredContent => $data,
  };
}

sub tool_error {
  my ($self, $message) = @_;

  return {
    isError => JSON::MaybeXS::true,
    content => [{
      type => 'text',
      text => $message,
    }],
  };
}

sub rpc_result {
  my ($self, $id, $result) = @_;

  return {
    jsonrpc => '2.0',
    id      => $id,
    result  => $result,
  };
}

sub rpc_error {
  my ($self, $id, $code, $message) = @_;

  return encode_json({
    jsonrpc => '2.0',
    id      => $id,
    error   => {
      code    => $code,
      message => $message,
    },
  });
}

1;
