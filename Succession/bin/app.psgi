#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";

use Plack::Builder;
use Succession;

use DateTime;
use DateTime::Format::HTTP;
use FindBin '$RealBin';

my $thirty_days = DateTime::Format::HTTP->format_datetime(DateTime->now->add(days => 30));

builder {
  enable 'Headers',
    when => ['Content-Type' => qr{^text/css}],
    set  => ['Expires' => $thirty_days, 'Cache-Control' => 'max-age=2592000'];
  enable 'Static', 
    path => qr{^/(images|css)/},
    root => "$RealBin/../public/";
  Succession->to_app;
}
