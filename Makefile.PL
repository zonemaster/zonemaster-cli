use 5.014002;
use strict;
use warnings FATAL => 'all';
use inc::Module::Install;

use ExtUtils::MakeMaker ();

name 'Zonemaster-CLI';
all_from 'lib/Zonemaster/CLI.pm';
resources(
    repository => 'https://github.com/zonemaster/zonemaster-cli',
    bugtracker => 'https://github.com/zonemaster/zonemaster-cli/issues',
);

tests_recursive( 't' );

# "2.1.0" could be declared as "2.001" but not as "2.1"
# (see Zonemaster::LDNS below)

requires(
    'JSON::XS'           => 0,
    'Locale::TextDomain' => 1.23,
    'MooseX::Getopt'     => 0,
    'Text::Reflow'       => 0,
    'Zonemaster::Engine' => 4.003,
    'Zonemaster::LDNS'   => 2.002,
);

# Make all platforms include inc/Module/Install/External.pm
requires_external_bin 'find';
if ($^O eq "freebsd") {
    requires_external_bin 'gmake';
};

sub MY::postamble {
    my $pure_all;
    my $sharemakefile = 'share/GNUmakefile';
    if ($^O eq "freebsd") {
        # Make FreeBSD use gmake for share
        $pure_all = "GMAKE ?= \"gmake\"\n"
            . "pure_all :: $sharemakefile\n"
            . "\tcd share && \$(GMAKE) all\n";
    } else {
        # Here Linux and GNU Make is assumed
        $pure_all = "pure_all :: $sharemakefile\n"
            . "\tcd share && \$(MAKE) all\n";
    };

    my $docker = <<'END_DOCKER';

docker-build:
	docker build --tag zonemaster/cli:local --build-arg version=$(VERSION) .

docker-tag-version:
	docker tag zonemaster/cli:local zonemaster/cli:$(VERSION)

docker-tag-latest:
	docker tag zonemaster/cli:local zonemaster/cli:latest

END_DOCKER

    return $pure_all . $docker;
};



install_script 'zonemaster-cli';
install_share;

WriteAll;
