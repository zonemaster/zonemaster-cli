use 5.014002;
use strict;
use warnings FATAL => 'all';
use inc::Module::Install;

use ExtUtils::MakeMaker ();

name 'Zonemaster-CLI';
license 'bsd';
all_from 'lib/Zonemaster/CLI.pm';

tests_recursive( 't' );

resources(
    repository => 'https://github.com/dotse/zonemaster-cli',
    bugtracker => 'https://github.com/dotse/zonemaster-cli/issues',
);

configure_requires( 'Locale::Msgfmt' => 0.15, );

build_requires( 'Test::More' => 0, );

requires(
    'JSON::XS'           => 0,
    'Locale::TextDomain' => 1.23,
    'MooseX::Getopt'     => 0,
    'Text::Reflow'       => 0,
    'Zonemaster::Engine' => 2.0,
    'Zonemaster::LDNS'   => 1.0,
);

sub MY::postamble {
        return <<'MAKE_FRAG';
	$(MYEXTLIB): share/Makefile
	cd share && $(MAKE) all
MAKE_FRAG
};

install_script 'zonemaster-cli';
install_share;

WriteAll;
