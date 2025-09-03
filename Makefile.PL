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
    'Readonly'           => 0,
    'Net::IP::XS'        => 0,
    'JSON::XS'           => 0,
    'Locale::TextDomain' => 1.23,
    'Try::Tiny'          => 0,
    'Zonemaster::LDNS'   => 5.000000,    # v5.0.0
    'Zonemaster::Engine' => 8.000000,    # v8.0.0
);

test_requires(
    'JSON::Validator'   => 0,
    'Test::Differences' => 0,
);

# Make all platforms include inc/Module/Install/External.pm
requires_external_bin 'find';
if ( $^O eq "freebsd" ) {
    requires_external_bin 'gmake';
}

sub MY::postamble {
    return <<'MAKE_END';

pure_all :: share/GNUmakefile
	$(MAKE) -C share all

.PHONY: docker-build
docker-build:
	docker build --tag zonemaster/cli:local --build-arg version=$(VERSION) .

.PHONY: docker-tag-version
docker-tag-version:
	docker tag zonemaster/cli:local zonemaster/cli:$(VERSION)

.PHONY: docker-tag-latest
docker-tag-latest:
	docker tag zonemaster/cli:local zonemaster/cli:latest

.PHONY: mydist
mydist:
	$(MAKE) -C share mo
	$(MAKE) tardist

MAKE_END
} ## end sub MY::postamble

install_script 'zonemaster-cli';
install_share;

makemaker_args( macro => { DIST_DEFAULT => 'mydist' } );

WriteAll;
