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
    'Net::Interface'     => 0,
    'MooseX::Getopt'     => 0,
    'Text::Reflow'       => 0,
    'Zonemaster::Engine' => 4.002,
    'Zonemaster::LDNS'   => 2.002,
);

# Make all platforms include inc/Module/Install/External.pm
requires_external_bin 'find';
if ($^O eq "freebsd") {
    requires_external_bin 'gmake';
};

sub MY::postamble {
    my $sharemakefile = 'share/GNUmakefile';
    if ($^O eq "freebsd") {
        # Make FreeBSD use gmake for share
        return "GMAKE ?= \"gmake\"\n"
            . "pure_all :: $sharemakefile\n"
            . "\tcd share && \$(GMAKE) touch-po all\n";
    } else {
        # Here Linux and GNU Make is assumed
        return "pure_all :: $sharemakefile\n"
            . "\tcd share && \$(MAKE) touch-po all\n";
    };
};



install_script 'zonemaster-cli';
install_share;

WriteAll;
