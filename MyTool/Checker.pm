package MyTool::Checker;
use strict;
use warnings;
use LWP::UserAgent;

sub get_latest {
    my ($pkg) = @_;
    my $ua = LWP::UserAgent->new(timeout => 10);
    my $res = $ua->get("https://example.com/releases.txt");
    if ($res->is_success) {
        if ($res->decoded_content =~ /MyTool\s+v?([0-9.]+)/) {
            return $1;
        }
    }
    return undef;
}

1;
