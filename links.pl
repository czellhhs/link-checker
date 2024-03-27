########################################################################
# Ensure perl distribution has following CPAN libraries installed
# with `sudo cpan install <name>` or `sudo cpanm install <name>`:
#  -- HTML::SimpleLinkExtor 
#  -- Text::Table::Tiny
#  -- IO::Socket::SSL::Utils
#
# If you're on UNIX/Linux (non-Macintosh) you may need to install the 
# following packages from your package manager in order for the 
# SSL library above to install (ymmv):
#  -- libnet-ssleay-perl
#  -- libcrypt-ssleay-perl
#
# Usage:
#
# CRAWLER_URL=https://<your-site-url> perl links.pl
#
########################################################################

use strict;
use warnings;
use HTML::SimpleLinkExtor;
use List::Util qw/uniq/;
use Text::Table::Tiny 1.02 qw/ generate_table /;

my $BASE_URL = $ENV{CRAWLER_URL};
if ( !$BASE_URL ) {
    die "NO BASE URL DEFINED IN ENV VAR 'CRAWLER_URL'\n";
}

my @already_visited   = ();
my @access_denied     = ();
my @redirectish_links = ();
my @wierd_links       = ();
my @not_found         = ();

sub CHECK_VISITED {
    my $path = shift;
    for my $p (@already_visited) {
        return 1 if $p eq $path;
    }

    return 0;
}

sub VISIT {
    my $path        = shift;
    my $owning_page = shift;
    print "Already visited count -> " . scalar @already_visited . "\n";
    print "Visiting: $path\n";
    my $extor = HTML::SimpleLinkExtor->new();
    $extor->ua->default_header( 'User-Agent' =>
'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36 Edg/121.0.0.0'
    );
    $extor->ua->add_handler(
        response_header => sub {
            my ( $response, $ua, $handler ) = @_;
            if ( $response->code == 404 ) {
                push @not_found, [ $path, $owning_page ];
            }
            elsif ( $response->code == 403 ) {
                push @access_denied, [$path, $owning_page];
            }
            elsif ( $response->code >= 301 && $response->code <= 304 ) {
                push @redirectish_links, [$path, $owning_page];
            }
            elsif ( $response->code != 200 ) {
                push @wierd_links,
                  "$path on page: $owning_page, status: " . $response->code;
                print STDERR "Got some wierd return back for $path: "
                  . $response->code . "\n";
            }
        }
    );
    if ( $path =~ m/^https:\/\// ) {

        # fully qualified link, just attempt to resolve it
        # not parse its response
        print "Testing ${path}\n";
        #$extor->parse_url($path);
        $extor->ua->get($path);
    }
    else {
        # assume relative to given root domain
        print "Parsing ${BASE_URL}${path}\n";
        $extor->parse_url("${BASE_URL}${path}");
    }

    # if this is an https link; we're assuming its an external
    # link to the target domain; and we don't care about links on THAT page
    # otherwise we'll comb the internet...
    # so exit here on that condition
    if ( $path =~ m/^https:\/\// ) {
        push @already_visited, $path;
        return ();
    }

    # include links that are relative (start with '/') and links that start with 'https'
    # but filter out links to '/#', the current $path itself, and
    # any we've already seen/visited
    my @page_links = grep {
             ( $_ =~ m/^\// || $_ =~ m/^https:\/\// )
          && $_ !~ m/^\/#/
          && $_ !~ m/^$path$/
          && !CHECK_VISITED($_)
    } $extor->a;

    # uniq the list of links
    @page_links = uniq @page_links;

    # add them to already seen list
    push @already_visited, $path;
    push @already_visited, @page_links;

    # uniq already seen list
    @already_visited = uniq @already_visited;

    # return the list of unique links on page rendered at $path
    return @page_links;
}

sub TRAVERSE {
    my $path        = shift;
    my $owning_page = shift;
    my @links;
    do {
        @links = VISIT( $path, $owning_page );
        print "Found links numbering: " . scalar @links . "\n";
        TRAVERSE( $_, $path ) for @links;
    } while ( @links > 0 );
}

# kick it off!
TRAVERSE( '/', '/' );

print "==================\n";
print "CRAWLING COMPLETE!\n";
print "==================\n";
print "Crawled total of " . scalar @already_visited . " unique links/hrefs\n";
print "404's:\n";
print generate_table(rows => \@not_found, header => [ '404 link', 'page']), "\n";
print "\n";
print "403's:\n";
print generate_table(rows => \@access_denied, header => [ '403 link', 'page']), "\n";
print "\n";

# Uncomment to show redirect's and other's
# print "Redirect-ish:\n";
# print join "\n", @redirectish_links;
# print "\n";
# print "Wierd Ones:\n";
# print join "\n", @wierd_links;
# print "\n";
