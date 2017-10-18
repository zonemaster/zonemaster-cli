# Installation

## Overview

This document describes prerequisites, installation and post-install sanity
checking for Zonemaster::CLI. The final section wraps up with a few pointer to
other interfaces to Zonemaster. For an overview of the Zonemaster product,
please see the [main Zonemaster Repository].


## Prerequisites

Before installing Zonemaster::CLI, you should [install Zonemaster::Engine][
Zonemaster::Engine installation].

> **Note:** [Zonemaster::Engine] and [Zonemaster::LDNS] are dependencies of
> Zonemaster::CLI. Zonemaster::LDNS has a special installation requirement,
> and Zonemaster::Engine has a list of dependencies that you may prefer to
> install from your operating system distribution (rather than CPAN).
> We recommend following the Zonemaster::Engine installation instruction.

For details on supported versions of Perl and operating system for
Zonemaster::CLI, see the [declaration of prerequisites].


## Installation

This instruction covers the following operating systems:

 * [CentOS](#1-centos)
 * [Debian](#2-debian)
 * [FreeBSD](#3-freebsd)
 * [Ubuntu](#4-ubuntu)


### 1. CentOS

First install the Zonemaster Engine, following the instructions above.

1) Install the CPAN packages.

`sudo cpan -i Zonemaster::CLI`


### 2. Debian

1) Install necessary packages.

`sudo apt-get install libmoosex-getopt-perl libtext-reflow-perl libmodule-install-perl`

2) Install non-packaged software

`sudo cpan -i Zonemaster::CLI`

3) Now you are ready to run the zonemaster-cli command:

`zonemaster-cli zonemaster.net`


### 3. FreeBSD

1) Still as root, install necessary packages.

`pkg install p5-MooseX-Getopt p5-Text-Reflow p5-Module-Install`

2) Still as root, install non-packaged software.

`cpan -i Zonemaster::CLI`

3) The CLI tool is now installed and can be run by any user.

`$ zonemaster-cli zonemaster.net`


### 4. Ubuntu

Use the procedure for installation on [Debian](#2-debian).


## What to do next?

 * For a web GUI, follow the [Zonemaster::Backend][Zonemaster::Backend
   installation] and [Zonemaster::GUI installation] instructions.
 * For a [JSON-RPC][JSON-RPC API] frontend, follow the [Zonemaster::Backend
   installation] instruction.

-------

[Declaration of prerequisites]: https://github.com/dotse/zonemaster/blob/master/README.md#prerequisites
[JSON-RPC API]: https://github.com/dotse/zonemaster-backend/blob/master/docs/API.md
[Main Zonemaster repository]: https://github.com/dotse/zonemaster/blob/master/README.md
[Zonemaster::Backend installation]: https://github.com/dotse/zonemaster-backend/blob/master/docs/Installation.md
[Zonemaster::Engine installation]: https://github.com/dotse/zonemaster-engine/blob/master/docs/Installation.md
[Zonemaster::Engine]: https://github.com/dotse/zonemaster-engine/blob/master/README.md
[Zonemaster::GUI installation]: https://github.com/dotse/zonemaster-gui/blob/master/docs/installation.md
[Zonemaster::LDNS]: https://github.com/dotse/zonemaster-ldns/blob/master/README.md

Copyright (c) 2013 - 2017, IIS (The Internet Foundation in Sweden) \
Copyright (c) 2013 - 2017, AFNIC \
Creative Commons Attribution 4.0 International License

You should have received a copy of the license along with this
work.  If not, see <http://creativecommons.org/licenses/by/4.0/>.
