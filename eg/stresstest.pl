#!/usr/bin/perl

#------------------------------------------------------------------------------
#
# Standard pragmas
#
#------------------------------------------------------------------------------

use strict;
use warnings;

require v5.6.0;

use WWW::SimpleRobot;
use LWP::Simple;
use Getopt::Long;
use Time::HiRes qw(gettimeofday);
use File::Basename;

our( 

    $INSTALL_DIR, 
    $VERSION,

    $opt_logdir, 
    $opt_clients, 
    $opt_times, 
    $opt_depth,

    $url, 

    $base_url,

    $t0,
    %cache,

);

sub usage()
{
    die <<EOF;
Usage: $0 
    [ -clients <no. clients> ] 
    [ -times <no. times> ]
    [ -depth <depth> ] 
    <url>
EOF
}

sub verbose( @ )
{
    my $dt = gettimeofday - $t0;
    print STDERR join( "\t", scalar( localtime ), $_[0], $dt ), "\n";
}

$VERSION = '0.001';

$opt_times = 1;
$opt_clients = 1;
$opt_depth = 1;
$opt_logdir = $INSTALL_DIR;

GetOptions( qw( times=i depth=i clients=i ) ) and $url = shift
    or usage
;

$INSTALL_DIR = dirname( $0 );
$SIG{CHLD} = 'IGNORE';

my $base_uri = URI->new( $url );
$base_url = $base_uri->scheme . '://' . $base_uri->authority . '/';
my $robot = WWW::SimpleRobot->new(
    URLS            => [ $url ],
    FOLLOW_REGEX    => "^$base_url",
    DEPTH           => $opt_depth,
    VISIT_CALLBACK  =>
    sub { 
        my ( $url, undef, undef, $links ) = @_;
        my $dt = gettimeofday - $t0;
        verbose $url;
        for my $link ( @$links )
        {
            my ( $tag, %attr ) = @$link;
            next unless $tag eq 'img' and my $src = $attr{src};
            $src = URI->new_abs( $src, $url )->canonical->as_string;
            next if $cache{$src}++;
            if ( get( $src ) )
            {
                verbose $src; 
            }
        }
    }
);
for my $child_no ( 1 .. $opt_clients )
{
    my $logfile = "$INSTALL_DIR/log.$child_no";
    if ( -e $logfile )
    {
        die "Can't delete $logfile: $!\n" unless unlink $logfile;
    }
}
for ( 1 .. $opt_times )
{
    $t0 = gettimeofday;
    %cache = ();
    for my $child_no ( 1 .. $opt_clients )
    {
        my $pid = fork();
        die "Can't fork: $!\n" unless defined $pid;
        if ( not $pid ) # child
        {
            my $logfile = "$INSTALL_DIR/log.$child_no";
            open( STDERR, ">>$logfile" )
                or die "Can't open $logfile: $!\n"
            ;
            verbose "start";
            $robot->traverse( $url );
            my $dt = gettimeofday - $t0;
            verbose "end";
            exit;
        }
    }
}

#------------------------------------------------------------------------------
#
# Start of POD
#
#------------------------------------------------------------------------------

=head1 NAME

stresstest.pl

=head1 SYNOPSIS

Usage: ./stresstest.pl
    [ -clients <no. clients> ]
    [ -times <no. times> ]
    [ -depth <depth> ]
    <base url>

=head1 DESCRIPTION

stresstest.pl is a perl script that stress tests a website. Given a URL, it
will "spider" from that URL, requesting all pages linked from it, and all
images on each page. It will only follow links on the same site (from the same
host). It can be configured, using command line options, to traverse links to a
particular depth (default 1), to do the traversal a number of times (default 1)
and to fork a number of concurrent clients to do seperate traversals (default
1).

Each fork'ed client will log its activity in a logfile called "log.n", where n
is the number of the client in a logging directory (default the install dir of
the script). The log lists all requests, with time of request and total elapsed
time in a tab seperated format; e.g.:



The stresstester tries to mimic a browser; i.e. it will "cache" images, and
only request them once.

=head1 AUTHOR

Ave.Wrigley@itn.co.uk

=head1 COPYRIGHT

Copyright (c) 2001 Ave Wrigley. All rights reserved. This program is free
software; you can redistribute it and/or modify it under the same terms as Perl
itself.

=cut

#------------------------------------------------------------------------------
#
# End of POD
#
#------------------------------------------------------------------------------
