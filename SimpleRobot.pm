package WWW::SimpleRobot;

#==============================================================================
#
# Standard pragmas
#
#==============================================================================

require 5.005_62;
use strict;
use warnings;

#==============================================================================
#
# Required modules
#
#==============================================================================

use URI;
use LWP::Simple;
use HTML::LinkExtor;

#==============================================================================
#
# Private globals
#
#==============================================================================

our $VERSION = '0.01';
our %OPTIONS = (
    URLS                => [],
    FOLLOW_REGEX        => '',
    VISIT_CALLBACK      => sub {},
    VERBOSE             => 0,
    DEPTH               => undef,
);

#==============================================================================
#
# Private methods
#
#==============================================================================

sub _verbose
{
    my $self = shift;

    return unless $self->{VERBOSE};
    print STDERR @_;
}

#==============================================================================
#
# Constructor
#
#==============================================================================

sub new
{
    my $class = shift;
    my %args = ( %OPTIONS, @_ );

    for ( keys %args )
    {
        die "Unknown option $_\n" unless exists $OPTIONS{$_};
    }

    my $self = bless \%args, $class;

    return $self;

}

#==============================================================================
#
# Public methods
#
#==============================================================================

sub traverse
{
    my $self = shift;

    die "No URLS specified in constructor\n" unless @{$self->{URLS}};
    $self->_verbose( 
        "Creating list of files to index from @{$self->{URLS}}...\n"
    );
    my @pages;
    for my $url ( @{$self->{URLS}} )
    {
        my $uri = URI->new( $url );
        die "$uri is not a valid URL\n" unless $uri;
        die "$uri is not a valid URL\n" unless $uri->scheme;
        die "$uri is not a web page\n" unless $uri->scheme eq 'http';
        die "can't HEAD $uri\n" unless
            my ( $content_type, $document_length, $modified_time ) =
                head( $uri )
        ;
        push( @pages, 
            { 
                modified_time => $modified_time,
                url => $uri->canonical, 
                depth => 0,
            }
        );
    }
    my %seen;
    for my $page ( @pages )
    {
        my $url = $page->{url};
        $self->_verbose( "GET $url\n" );
        my $html = get( $url ) or next;
        $self->{VISIT_CALLBACK}( $url, $html );
        next if defined( $self->{DEPTH} ) and $page->{depth} == $self->{DEPTH};
        $self->_verbose( "Extract links from $url\n" );
        my $linkxtor = HTML::LinkExtor->new( undef, $url );
        $linkxtor->parse( $html );
        for my $link ( $linkxtor->links )
        {
            my ( $tag, %attr ) = @$link;
            next unless $tag eq 'a';
            next unless my $href = $attr{href};
            $href =~ s/[#?].*$//;
            next unless $href = URI->new( $href );
            $href = $href->canonical->as_string;
            next unless $href =~ /$self->{FOLLOW_REGEX}/;
            my ( $content_type, undef, $modified_time ) = head( $href );
            next unless $content_type;
            next unless $content_type eq 'text/html';
            next if $seen{$href}++;
            my $npages = @pages;
            my $nseen = keys %seen;
            push( @pages, 
                { 
                    modified_time => $modified_time, 
                    url => $href, 
                    depth => $page->{depth}+1,
                }
            );
            $self->_verbose( "$nseen/$npages : $url : $href\n" );
        }
    }
    $self->{pages} = \@pages;
    $self->{urls} = [ map { $_->{url} } @pages ];
}

#==============================================================================
#
# AUTOLOADed accessor methods
#
#==============================================================================

sub AUTOLOAD
{
    my $self = shift;
    my $value = shift;
    use vars qw( $AUTOLOAD );
    my $method_name = $AUTOLOAD;
    $method_name =~ s/.*:://;
    $self->{$method_name} = $value if defined $value;
    return $self->{$method_name};
}

# Preloaded methods go here.

1;
__END__
# Below is stub documentation for your module. You better edit it!

=head1 NAME

WWW::SimpleRobot - a simple web robot for recursively following links on web
pages.

=head1 SYNOPSIS

    use WWW::SimpleRobot;
    my $robot = WWW::SimpleRobot->new(
        URLS            => [ 'http://www.perl.org/' ],
        FOLLOW_REGEX    => "^http://www.perl.org/",
        DEPTH           => 1,
        VISIT_CALLBACK  => 
            sub { my $url = shift; print STDERR "Visiting $url\n"; }
    );
    $robot->traverse;
    my @urls = @{$robot->urls};
    my @pages = @{$robot->pages};
    for my $page ( @pages )
    {
        my $url = $page->{url};
        my $depth = $page->{depth};
        my $modification_time = $page->{modification_time};
    }

=head1 DESCRIPTION

    A simple perl module for doing robot stuff. For a more elaborate interface,
    see WWW::Robot. This version uses LWP::Simple to grab pages, and
    HTML::LinkExtor to extract the links from them. Only href attributes of
    anchor tags are extracted. Extracted links are checked against the
    FOLLOW_REGEX regex to see if they should be followed. A HEAD request is
    made to these links, to check that they are 'text/html' type pages. 

=head1 BUGS

    This robot doesn't respect the Robot Exclusion Protocol
    (http://info.webcrawler.com/mak/projects/robots/norobots.html) (naughty
    robot!), and doesn't do any exception handling if it can't get pages - it
    just ignores them and goes on to the next page!

=head1 AUTHOR

Ave Wrigley <Ave.Wrigley@itn.co.uk>

=head1 COPYRIGHT

Copyright (c) 2001 Ave Wrigley. All rights reserved. This program is free
software; you can redistribute it and/or modify it under the same terms as Perl
itself.

=cut
