# Zonemaster CLI installation guide

This is the installation instructions for the Zonemaster CLI utility.

The documentation covers the following operating systems:

 * [1] <a href="#Debian">Ubuntu 12.04 (LTS)</a>
 * [2] <a href="#Debian">Debian Jessie (version 8) - 64 bits</a>
 * [3] <a href="#FreeBSD">FreeBSD 10.1</a>
 * [4] <a href="#CentOS">CentOS 7 </a>

>
> Note: We assume the installation instructions will work for earlier OS
> versions too. If you have any issue in installing the Zonemaster engine with
> earlier versions, please send a mail with details to contact@zonemaster.net
>


## Prerequisite

Before you install the Zonemaster CLI utility, you need the
Zonemaster Engine test framework installed. Please see the
[Zonemaster Engine installation instructions](https://github.com/dotse/zonemaster-engine/blob/master/docs/installation.md).

To install the CLI, one installs the dependecies
for the chosen OS and then finally install the CLI itself.

### <a name="Debian"></a> Install dependencies for Debian & Ubuntu

1) Install necessary packages.

`sudo apt-get install libmoosex-getopt-perl libtext-reflow-perl libmodule-install-perl`

2) Install non-packaged software

`sudo cpan -i Zonemaster::CLI`

3) Now you are ready to run the zonemaster-cli command:

`zonemaster-cli zonemaster.net`


## <a name="FreeBSD"></a> Install dependencies for FreeBSD

1) Still as root, install necessary packages.

`pkg install p5-MooseX-Getopt p5-Text-Reflow p5-Module-Install`

2) Still as root, install non-packaged software.

`cpan -i Zonemaster::CLI`

3) The CLI tool is now installed and can be run by any user.

`$ zonemaster-cli zonemaster.net`


## <a name="CentOS"></a> Install dependencies for CentOS 7

First install the Zonemaster Engine, following the instructions above.

1) Install the CPAN packages.

`sudo cpan -i Zonemaster::CLI`


## What to do next?

In case if you want to use the engine from a web interface, you will have to install the
*[Backend](https://github.com/dotse/zonemaster-backend/blob/master/docs/installation.md)*
and the *[GUI](https://github.com/dotse/zonemaster-gui/blob/master/docs/installation.md)*.
To use the engine from the *[API](https://github.com/dotse/zonemaster-backend/blob/master/docs/API.md)*,
you will have to install the *Backend*.


-------

Copyright (c) 2013 - 2016, IIS (The Internet Foundation in Sweden)  
Copyright (c) 2013 - 2016, AFNIC  
Creative Commons Attribution 4.0 International License

You should have received a copy of the license along with this
work.  If not, see <http://creativecommons.org/licenses/by/4.0/>.
