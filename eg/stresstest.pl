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
use Pod::Text;

our( 

    $INSTALL_DIR, 
    $VERSION,

    $opt_logdir, 
    $opt_clients, 
    $opt_times, 
    $opt_depth,
    $opt_help,
    $opt_doc,

    $url, 

    $base_url,

    $t0,
    $total_bytes,
    %cache,

);

sub usage()
{
    die <<EOF;
Usage: $0 
    [ -clients <no. clients> ] 
    [ -times <no. times> ]
    [ -depth <depth> ] 
    [ -help ]
    [ -doc ]
    <url>
EOF
}

$total_bytes = 0;

sub nicely( $ )
{
    my $bits = shift;
    if ( $bits >= 1_000_000 )
    {
        return sprintf( "%0.2fM", $bits / 1_000_000 );
    }
    if ( $bits >= 1_000 )
    {
        return sprintf( "%0.2fK", $bits / 1_000 );
    }
    else
    {
        return $bits;
    }
}

sub log_( @ )
{
    my $url = shift;
    my $bytes = shift;

    $total_bytes += $bytes;
    my $dt = gettimeofday - $t0;
    print LOG join( "\t", scalar( localtime ), $url, $bytes, $total_bytes, $dt ), "\n";
}

$VERSION = '0.001';

$opt_times = 1;
$opt_clients = 1;
$opt_depth = 0;
$opt_logdir = $INSTALL_DIR;

GetOptions( qw( help doc times=i depth=i clients=i ) ) 
    or usage
;
usage if $opt_help;
Pod::Text->new->parse_from_file( $0, '-' ) and exit if $opt_doc;
$url = shift or die usage;

$INSTALL_DIR = dirname( $0 );

my $base_uri = URI->new( $url );
$base_url = $base_uri->scheme . '://' . $base_uri->authority . '/';
my $robot = WWW::SimpleRobot->new(
    URLS            => [ $url ],
    FOLLOW_REGEX    => "^$base_url",
    DEPTH           => $opt_depth,
    VISIT_CALLBACK  =>
    sub { 
        my ( $url, undef, $html, $links ) = @_;
        log_ $url, length( $html );
        for my $link ( @$links )
        {
            my ( $tag, %attr ) = @$link;
            next unless $tag eq 'img' and my $src = $attr{src};
            $src = URI->new_abs( $src, $url )->canonical->as_string;
            next if $cache{$src}++;
            if ( my $img = get( $src ) )
            {
                log_ $src, length( $img ); 
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
pipe( FROM_CHILD, TO_PARENT ) or die "pipe: $!\n";
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
            close( FROM_CHILD );
            my $logfile = "$INSTALL_DIR/log.$child_no";
            open( LOG, ">>$logfile" )
                or die "Can't open $logfile: $!\n"
            ;
            log_ "start", 0;
            $robot->traverse( $url );
            log_ "end", 0;
            print TO_PARENT "$total_bytes\n";
            exit;
        }
        else # parent
        {
            print STDERR "$pid launched\n";
        }
    }
}

close( TO_PARENT );
my $grand_total = 0;
while ( my $total_bytes = <FROM_CHILD> )
{
    chomp( $total_bytes );
    $grand_total += $total_bytes
}
print STDERR "wait ...\n";
my $pid;
while ( ( $pid = wait ) != -1 )
{
    print STDERR "$pid finished\n";
}

my $dt = gettimeofday - $t0;
my $bps = nicely( $grand_total * 2^8 / $dt );
print STDERR "$grand_total bytes delivered in $dt seconds (${bps}bps)\n";

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
the script). The log lists all requests, with time of request, bytes
transfered, total bytes transfered, and total elapsed time in a tab seperated
format; e.g.:

Mon May 14 12:36:13 2001        http://www.itn.co.uk/   51691   51691   1.342589        02072906

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
