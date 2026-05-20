package Succession::RouteHelpers;

use Moo;
use experimental 'signatures'; # After Moo because Moo turns all warnings on

use Succession::App;

sub make_app ($self, $params) {

  my $args = {
    request => $params->{request},
  };

  for (qw[date list_size]) {
    $args->{$_} = $params->{$_} if defined $params->{$_};
  }

  return Succession::App->new($args);
}

sub is_not_modified ($self, $request, $etag, $last_mod) {

  my $if_none_match = $request->header('If-None-Match');
  my $if_modified   = $request->header('If-Modified-Since');

  return 1 if defined $if_none_match && $if_none_match eq $etag;
  return 1 if defined $if_modified && $if_modified eq $last_mod;

  return 0;
}

sub parse_frontmatter ($self, $content) {
  my $title;

  if ($content =~ /\A---\n(.*?)\n---\n/s) {
    my $fm = $1;
    ($title) = $fm =~ /^title:\s*(.+?)\s*$/m;
    $content =~ s/\A---\n.*?\n---\n//s;
  }

  return ($title, $content);
}

1;
