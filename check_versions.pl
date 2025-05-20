#!/usr/bin/env perl
use YAML::XS qw(LoadFile);
use LWP::UserAgent;
use JSON qw(decode_json);
use HTML::TreeBuilder;
use utf8;
use feature 'say';

use MyTool::Checker
#use Module::Load;
#use Data::Dumper;

my $ua = LWP::UserAgent->new(timeout => 10);
$ua->agent("VersionChecker/1.0");

my $input_file = shift || "MyPackages.yaml";

# my $output_file = "cv_output";
# open my $fh, ">", $output_file or die();

my $packages = LoadFile($input_file);

foreach my $pkg (@$packages) {
    my $name = $pkg->{name};
    my $current = $pkg->{current};
    my $type = $pkg->{type};
    my $url = $pkg->{url};
    my $parser = $pkg->{parser};
    my $latest;

    if ($type eq 'github') {
        $latest = check_github($url);
	#$latest = undef;
    } elsif ($type eq 'github-snapshot') {
	$latest = check_github_snapshot($url);
	#$latest = undef;
    } elsif ($type eq 'website-href') {
        $latest = check_website($url, $pkg->{match}, 'href');
    } elsif ($type eq 'website-text') {
        $latest = check_website($url, $pkg->{match}, 'text');
    } elsif ($type eq 'website-href-reverse') { # when you want the *last* link in a list
        $latest = check_website($url, $pkg->{match}, 'reverse');
    } elsif ($type eq 'custom') {
        load $parser;
        $latest = $parser->get_latest($pkg);
    } else {
        warn "Unknown type '$type' for $name\n";
        next;
    }

    if (defined $latest && $latest ne $current) {
	binmode(STDOUT, ":utf8");
        print "\x{274C} $name: $current → $latest\n";
    } elsif (! defined $latest) {
	binmode(STDOUT, ":utf8");
        print "\x{2753} $name: N/A \n";
    } else {
	binmode(STDOUT, ":utf8");
        print "\x{2705} $name: up to date ($current)\n";
    }
}

# === GitHub handler ===
sub check_github {
    my ($url) = @_;
    if ($url =~ m{https://github.com/([^/]+/[^/]+)}) {
        my $repo = $1;
        my $api_url = "https://api.github.com/repos/$repo/releases/latest";
        my $res = $ua->get($api_url);
        if ($res->is_success) {
            my $data = decode_json($res->decoded_content);
            return clean_version($data->{tag_name});
        } else {
            warn "GitHub fetch failed for $repo: " . $res->status_line . "\n";
        }
    }
    return undef;
}

sub check_github_snapshot {
    my ($url) = @_;
    my $repo = $url."/commits";
    my $res = $ua->get($repo);
    if ($res->is_success) {
	my $tree = HTML::TreeBuilder->new_from_content($res->decoded_content);
        my @links = $tree->look_down(_tag => 'a');
        foreach my $link (@links) {
	    my $href = $link->attr('href');
	    if ($href =~ m|/commit/(\w*)|) {
		return $1;
	    }
	}
    } else {
	warn "Website fetch failed on $url: " . $res->status_line . "\n";
    }
    return undef;
}
    
# === Website handler (requires match regex) ===
sub check_website {
    my ($url, $match, $subtype) = @_;

    if ($url =~ m{^(.*?/)[^/]+\.(?:tar\.(?:gz|bz2)|tgz|xz|gz)$}) {
	$url = $1;
    }

    my $res = $ua->get($url);
    if ($res->is_success) {
        my $tree = HTML::TreeBuilder->new_from_content($res->decoded_content);
        my @links = $tree->look_down(_tag => 'a');
	@links = reverse @links if $subtype eq 'reverse';
        foreach my $link (@links) {
            my $text = $link->as_text;
            my $href = $link->attr('href');
            my $reg = qr($match);
            if ($subtype eq 'href' && $href =~ /$reg/) {
                return $1;
            } elsif ($subtype eq 'text' && $text =~ /$reg/) {
		return $1;
	    } elsif ($subtype eq 'reverse' && $href =~ /$reg/) {
		return $1;
	    }
        }
    } else {
        warn "Website fetch failed for $url: " . $res->status_line . "\n";
    }
    return undef;
}

sub clean_version {
    my ($v) = @_;
    $v =~ s/^v//;
    return $v;
}

