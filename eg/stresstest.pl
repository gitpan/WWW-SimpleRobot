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

my $k = 1024;
my $m = $k * $k;

sub nicely( $ )
{
    my $bits = shift;
    if ( $bits >= $m )
    {
        return sprintf( "%0.2f M", $bits / $m );
    }
    if ( $bits >= $k )
    {
        return sprintf( "%0.2f K", $bits / $k );
    }
    else
    {
        return "$bits ";
    }
}

sub log_( @ )
{
    my $url = shift;
    my $bytes = shift;
    my $type = shift;

    my $dt = gettimeofday - $t0;
    if ( $type =~ /^(page|image)$/ )
    {
        print "$type $bytes\n";
    }
    print LOG join( "\t", scalar( localtime ), $url, $bytes, $dt ), "\n";
}

$VERSION = '0.001';

$opt_times = 1;
$opt_clients = 1;
$opt_depth = 0;
$opt_logdir = $INSTALL_DIR;

GetOptions( qw( help doc times=i depth=i clients=s ) ) 
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
        log_ $url, length( $html ), 'page';
        for my $link ( @$links )
        {
            my ( $tag, %attr ) = @$link;
            next unless $tag eq 'img' and my $src = $attr{src};
            $src = URI->new_abs( $src, $url )->canonical->as_string;
            next unless $src =~ /^$base_url/;
            next if $cache{$src}++;
            if ( my $img = get( $src ) )
            {
                log_ $src, length( $img ), 'image';
            }
        }
    }
);
for my $clients ( split( ',', $opt_clients ) )
{
    for my $child_no ( 1 .. $clients )
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
        for my $child_no ( 1 .. $clients )
        {
            my $pid = fork();
            die "Can't fork: $!\n" unless defined $pid;
            if ( not $pid ) # child
            {
                select TO_PARENT;
                $|++;
                close( FROM_CHILD );
                my $logfile = "$INSTALL_DIR/log.$child_no";
                open( LOG, ">>$logfile" )
                    or die "Can't open $logfile: $!\n"
                ;
                log_ "start", 0, 'info';
                $robot->traverse( $url );
                log_ "end", 0, 'info';
                exit;
            }
            else # parent
            {
            }
        }
    }

    close( TO_PARENT );

    my $total_bytes = 0;
    my $total_pages = 0;
    my $total_images = 0;

    while ( my $log = <FROM_CHILD> )
    {
        chomp( $log );
        my ( $type, $bytes ) = split( ' ', $log );
        $total_pages += $type eq 'page';
        $total_images += $type eq 'image';
        $total_bytes += $bytes;
        print STDERR nicely( $total_bytes ), " bytes\r";
    }
    while ( ( my $pid = wait ) != -1 ) { }
    my $dt = gettimeofday - $t0;
    my $secs = sprintf( "%0.2f", $dt );
    my $bits_per_byte = 8;
    my $bits = $total_bytes * $bits_per_byte;
    my $bps = $bits / $dt;
    print STDERR 
        "$total_pages pages and $total_images images (",
        nicely( $total_bytes ), 
        " bytes) delivered to $clients concurrent users in $secs seconds (",
        nicely( $bps ),
        "bps)\n"
    ;
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
