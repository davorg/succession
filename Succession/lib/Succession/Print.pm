package Succession::Print;

use strict;
use warnings;
use utf8;
use Encode qw(encode);
use File::Temp ();
use Path::Tiny qw(path);
use MIME::Base64 qw(encode_base64);
use feature 'state';

# Public previews are rasterised after watermarking; clean vectors never leave
# the server. Temporary files are private and removed even if conversion fails.
sub preview_png {
  my ($class, $svg) = @_;
  my $watermark = '<text x="148.5" y="210" text-anchor="middle" dominant-baseline="middle" '
    . 'transform="rotate(-35 148.5 210)" font-family="sans-serif" font-weight="bold" '
    . 'font-size="39" letter-spacing="3" fill="#173A6A" opacity="0.24">SPECIMEN</text>';
  $svg =~ s{</svg>\s*\z}{$watermark</svg>} or die "Invalid preview SVG\n";
  my $dir = File::Temp->newdir;
  my $input = path("$dir", 'preview.svg');
  my $output = path("$dir", 'preview.png');
  $input->spew_raw(encode('UTF-8', $svg));
  system('rsvg-convert', '--width', '1000', '--output', "$output", "$input") == 0
    or die "Unable to render print preview\n";
  return $output->slurp_raw;
}

# Presentation only: the model supplies historical facts and child ordering.
sub render {
  my ($class, %args) = @_;
  die "Unsupported print size\n" unless ($args{size} // 'A3') eq 'A3';
  my @rows;
  my $flatten;
  $flatten = sub {
    my ($node, $depth) = @_;
    push @rows, [$node, $depth];
    $flatten->($_, $depth + 1) for @{ $node->{children} // [] };
  };
  $flatten->($args{data}, 0);
  undef $flatten;

  # Refuse overcrowding rather than silently clipping or making text tiny.
  return undef if @rows > 40 || grep { $_->[1] > 8 } @rows;
  # Reserve a little extra space before each major family branch.
  my @positions;
  my $units = 0;
  for my $i (0 .. $#rows) {
    $units += 0.45 if $i > 1 && $rows[$i][1] == 1;
    push @positions, $units++;
  }
  # Give shorter hierarchies a generous illustrated footer; longer prints
  # retain their row space and use a smaller architectural vignette.
  my $illustration_height = @rows <= 32 ? 70 : 20;
  my $spacing = (320 - $illustration_height) / ($units > 26 ? $units : 26);
  state $windsor = encode_base64(path(__FILE__)->absolute->parent(3)
    ->child('share', 'print', 'windsor-engraving.png')->slurp_raw, '');
  state $crown = encode_base64(path(__FILE__)->absolute->parent(3)
    ->child('share', 'print', 'crown-engraving.png')->slurp_raw, '');
  my $date = $args{date}->strftime('%e %B %Y');
  $date =~ s/^\s+//;
  my @svg = (
    '<svg xmlns="http://www.w3.org/2000/svg" width="297mm" height="420mm" viewBox="0 0 297 420">',
    '<rect width="297" height="420" fill="#FBF8ED"/>',
    '<path d="M14 6 H283 Q283 14 291 14 V406 Q283 406 283 414 H14 Q14 406 6 406 V14 Q14 14 14 6 Z" fill="none" stroke="#916D20" stroke-width="0.45"/>',
    '<path d="M15 7.5 H282 Q282 15 289.5 15 V405 Q282 405 282 412.5 H15 Q15 405 7.5 405 V15 Q15 15 15 7.5 Z" fill="none" stroke="#BBA369" stroke-width="0.2"/>',
    '<g font-family="Georgia, Times New Roman, serif" fill="#092957">',
    _text(148.5, 23, 11.5, 'The British Line', 'text-anchor="middle" font-weight="bold"'),
    _text(148.5, 36, 11.5, 'of Succession', 'text-anchor="middle" font-weight="bold"'),
    _text(148.5, 48, 8, "on $date", 'text-anchor="middle" fill="#916D20"'),
    _text(148.5, 57, 3.8, 'The family of ' . $args{data}{name} . ' on this date.',
      'text-anchor="middle" font-style="italic"'),
    qq{<image x="15" y="13" width="45" height="40" preserveAspectRatio="xMidYMid meet" href="data:image/png;base64,$crown"/>},
    qq{<image x="237" y="13" width="45" height="40" preserveAspectRatio="xMidYMid meet" href="data:image/png;base64,$crown"/>},
    _text(243, 61, 3.5, 'Age', 'text-anchor="middle"'),
    _text(243, 66, 3.5, 'on this date', 'text-anchor="middle"'),
    _text(277, 61, 3.5, 'Position', 'text-anchor="middle"'),
    _text(277, 66, 3.5, 'in succession', 'text-anchor="middle"'),
    '<path d="M260 57 V' . (390 - $illustration_height) . '" stroke="#AD945A" stroke-width="0.25"/>',
  );

  # Each stem joins a parent's children, never their succession positions.
  for my $i (0 .. $#rows) {
    my $depth = $rows[$i][1];
    my @children;
    for my $j ($i + 1 .. $#rows) {
      last if $rows[$j][1] <= $depth;
      push @children, $j if $rows[$j][1] == $depth + 1;
    }
    next unless @children;
    # Inset stems slightly beneath the parent's initial letter.
    my $x = 22.2 + $depth * 11;
    my $top = 77.35 + $positions[$i] * $spacing;
    my $bottom = 74.35 + $positions[$children[-1]] * $spacing;
    push @svg, qq{<path d="M$x $top V$bottom" fill="none" stroke="#526780" stroke-width="0.3"/>};
    for my $child (@children) {
      my $y = 74.35 + $positions[$child] * $spacing;
      my $end = $x + 6;
      push @svg, qq{<path d="M$x $y H$end" stroke="#526780" stroke-width="0.3"/>};
    }
  }

  for my $i (0 .. $#rows) {
    my ($node, $depth) = @{ $rows[$i] };
    my $x = 20 + 11 * $depth;
    my $y = 76 + $positions[$i] * $spacing;
    my $colour = $node->{current_sovereign} ? '#916D20'
      : $node->{alive_on_date} ? '#092957' : '#8D97A1';
    my $note = $node->{current_sovereign} ? 'Sovereign on this date' : $node->{exclusion_reason};
    my $details = defined $node->{born} ? 'born ' . _date($node->{born}) : '';
    if (!$node->{alive_on_date} && defined $node->{died}) {
      $details = (defined $node->{born} ? _date($node->{born}) . ' – ' : 'died ') . _date($node->{died});
    }
    $details = "  ($details)" if length $details;
    my $annotation = $note ? "  — $note" : '';
    # Conservative width estimate; compress only exceptionally long rows.
    # Inline tspans keep dates and annotations attached to the actual name.
    my $width = length($node->{name}) * 2.6 + length($details) * 1.5 + length($annotation) * 1.5;
    my $available = 227 - $x;
    my $fit = $width > $available ? qq{ textLength="$available" lengthAdjust="spacingAndGlyphs"} : '';
    my $name = _escape($node->{name});
    $name .= '<tspan dx="2" font-size="3.8" fill="#78889B">' . _escape($details) . '</tspan>';
    $name .= '<tspan dx="2" font-size="3.6" font-style="italic" fill="#677487">' . _escape($annotation) . '</tspan>' if $note;
    push @svg, qq{<text x="$x" y="$y" font-size="5.2" fill="$colour"$fit>$name</text>};
    push @svg, _text(243, $y, 3.8, $node->{age}, 'text-anchor="middle"')
      if $node->{alive_on_date} && defined $node->{age};
    if (defined(my $number = $node->{succession_number})) {
      my $cy = $y - 1.4;
      my $radius = $spacing < 10 ? $spacing * 0.4 : 4.4;
      push @svg, qq{<circle cx="277" cy="$cy" r="$radius" fill="#092957"/>},
        _text(277, $y, length($number) > 2 ? 3.5 : 4.3, $number, 'text-anchor="middle" fill="#FFFDF8"');
    } elsif ($node->{alive_on_date}) {
      push @svg, _text(277, $y, 3.8, '–', 'text-anchor="middle"');
    }
  }
  my $image_y = 396 - $illustration_height;
  push @svg, qq{<image x="12" y="$image_y" width="273" height="$illustration_height" preserveAspectRatio="xMidYMid meet" href="data:image/png;base64,$windsor"/>},
    _text(148.5, 398, 2.8, 'WINDSOR CASTLE', 'text-anchor="middle" letter-spacing="0.5"'),
    _text(148.5, 403, 3, 'A royal home for a thousand years', 'text-anchor="middle" font-style="italic" fill="#916D20"'),
    _text(148.5, 409, 2.8, 'lineofsuccession.co.uk', 'text-anchor="middle"'),
    '</g></svg>';
  return join "\n", @svg;
}

sub _date {
  my ($iso) = @_;
  my @months = qw(January February March April May June July August September October November December);
  return $iso unless $iso =~ /\A([0-9]{4})-([0-9]{2})-([0-9]{2})\z/;
  return (0 + $3) . ' ' . $months[$2 - 1] . ' ' . $1;
}

sub _escape {
  my ($text) = @_;
  $text =~ s/&/&amp;/g;
  $text =~ s/</&lt;/g;
  $text =~ s/>/&gt;/g;
  $text =~ s/"/&quot;/g;
  $text =~ s/'/&apos;/g;
  return $text;
}

sub _text {
  my ($x, $y, $size, $text, $attrs) = @_;
  $attrs //= '';
  return qq{<text x="$x" y="$y" font-size="$size" $attrs>} . _escape($text) . '</text>';
}

1;
