Zonemaster CLI
==============
[![Build Status](https://travis-ci.org/zonemaster/zonemaster-engine.svg?branch=master)](https://travis-ci.org/zonemaster/zonemaster-engine)
[![CPAN version](https://badge.fury.io/pl/Zonemaster-CLI.svg)](https://metacpan.org/pod/Zonemaster::CLI)

### Purpose

This Git repository is one of the components of the Zonemaster software and contains the source for the Zonemaster CLI utility.

For an overview of the Zonemaster software, please see the
[Zonemaster repository].

## Prerequisite

Before you install the Zonemaster CLI utility, you need the
Zonemaster Engine test framework installed. Please see the
[Zonemaster Engine installation instructions]

Installation
============

Installation instructions for the CLI
[installation] document.


### Configuration 

This repository does not need any specific configuration.


### Docker

To build a local image for Zonemaster CLI you need a [local Zonemaster Engine
base image].

Build a new local base image:

```sh
make all dist docker-build
```

Tag the local base image with the current version number:

```sh
make docker-tag-version
```

Tag the local base image as the latest version:

```sh
make docker-tag-latest
```

Test a zone using the local base image:

```sh
docker run --rm zonemtaster/cli:local zonemaster.net
```

### Documentation

Other than the installation documentation, no specific documentation is needed.
The [USING] document provides an overview on how to use the CLI.


### Participation, Contact and Bug reporting

For participation, contact and bug reporting, please see the main
[Zonemaster README].


License
=======

The software is released under the 2-clause BSD license. See separate LICENSE file.


[Installation]:                                   docs/Installation.md
[USING]:                                          USING.md
[Zonemaster Engine installation instructions]:    https://github.com/zonemaster/zonemaster-engine/blob/master/docs/Installation.md
[Zonemaster repository]:                          https://github.com/zonemaster/zonemaster
[Zonemaster README]:                              https://github.com/zonemaster/zonemaster/blob/master/README.md
[Local Zonemaster Engine base image]:             https://github.com/zonemaster/zonemaster/blob/master/README.md#docker

