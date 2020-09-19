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

requires(
    'JSON::XS'           => 0,
    'Locale::TextDomain' => 1.23,
    'MooseX::Getopt'     => 0,
    'Text::Reflow'       => 0,
    'Zonemaster::Engine' => 3.0,
    'Zonemaster::LDNS'   => 2.0,
);

sub MY::postamble {
        return <<'MAKE_FRAG';
pure_all :: share/Makefile
	cd share && $(MAKE) all
MAKE_FRAG
};

install_script 'zonemaster-cli';
install_share;

WriteAll;
