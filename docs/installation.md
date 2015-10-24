# Zonemaster CLI installation guide

This is the installation instructions for the Zonemaster CLI utility.

The documentation covers the following operating systems:

 * [1] <a href="#Debian">Ubuntu 12.04 (LTS)</a>
 * [2] <a href="#Debian">Ubuntu 14.04 (LTS)</a>
 * [3] <a href="#Debian">Debian Wheezy (version 7)</a>
 * [4] <a href="#FreeBSD">FreeBSD 10.1</a>
 * [5] <a href="#CentOS">CentOS 7 </a>

## Prerequisite

Before you install the Zonemaster CLI utility, you need the
Zonemaster Engine test framework installed. Please see the
[Zonemaster Engine installation instructions](https://github.com/dotse/zonemaster-engine/blob/master/docs/installation.md).


### <a name="Debian"></a> Instructions for Ubuntu 12.04, Ubuntu 14.04 and Debian 7

1) Install necessary packages.

`sudo apt-get install libmoosex-getopt-perl libtext-reflow-perl libmodule-install-perl`

2) Install non-packaged software

`sudo cpan -i Zonemaster::CLI`

3) Now you are ready to run the zonemaster-cli command:

`zonemaster-cli example.com`


## <a name="FreeBSD"></a> Instructions for FreeBSD 10.1

1) First install the Zonemaster Engine, following the instructions above.

2) Still as root, install necessary packages.

`pkg install p5-MooseX-Getopt p5-Text-Reflow p5-Module-Install`

3) Still as root, install non-packaged software.

`cpan -i Zonemaster::CLI`

4) The CLI tool is now installed and can be run by any user.

    $ zonemaster-cli example.com


## <a name="CentOS"></a> Instructions for CentOS 7

First install the Zonemaster Engine, following the instructions above.

1) Install the CPAN packages.

`sudo cpan -i Zonemaster::CLI`



-------

Copyright (c) 2013, 2014, 2015, IIS (The Internet Infrastructure Foundation)  
Copyright (c) 2013, 2014, 2015, AFNIC  
Creative Commons Attribution 4.0 International License

You should have received a copy of the license along with this
work.  If not, see <http://creativecommons.org/licenses/by/4.0/>.
