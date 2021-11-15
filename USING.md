# Using the CLI

## Table of contents
* [Docker or local installation](#Docker-or-local-installation)
* [Invoking the command line tool](#Invoking-the-command-line-tool)
* [Test reports](#Test-reports)
* [Translation]
* [Advanced use](#Advanced-use)


## Docker or local installation

The `zonemaster-cli` tool can be run from the command line of any computer that
meets one of the following requirements:

* Docker is installed on the computer, or
* Zonemaster-CLI has been installed on the computer.

### Using Docker

To run Zonemaster-CLI on Docker you have to make sure that Docker is installed
on the computer and that you can run Docker on it.
* Instructions for installation are found on Docker [get started] page.
* Run the command `docker ps` on the command line to verify that you can run
  Docker on the computer.

When Docker has been correctly installed, no more installation is needed to run
`zonemaster-cli`. Just follow the examples below.

### Local installation

To have an local installation of Zonemaster-CLI follow the
[installation instruction]. When installed, the examples below can be followed.


## Invoking the command line tool

The most basic use of the `zonemaster-cli` command is to just test a domain, e.g.
"zonemaster.net".

With Docker:
```sh
docker run -t --rm zonemaster/cli zonemaster.net
```

With local installation:
```sh
zonemaster-cli zonemaster.net
```

The output comes continuously as the tests are performed.
```
Seconds Level     Message
======= ========= =======
  21.39 WARNING   The DNSKEY with tag 54636 uses an algorithm number 5 (RSA/SHA1) which is not recommended to be used.
  21.80 WARNING   DNSKEY with tag 26280 and using algorithm 5 (RSA/SHA1) has a size (1024) smaller than the recommended one (2048).
  23.61 NOTICE    SOA 'refresh' value (10800) is less than the recommended one (14400).
```

The test and output can be modified with different options:

* If your machine is for some reason not configured for use with IPv6 you want to
  disable the use of IPv6 with the `--no-ipv6` option.
* If you want to have the test case from which the message is printed then
  include the `--show-testcase` option.
* If you want to see the messages translated into another language (see
  "[Translation]" section below) then include e.g. `--locale da` (Docker) or
  `--locale da_DK.UTF-8` (local installation).

The same test as above with the three options included:

```sh
docker run -t --rm zonemaster/cli zonemaster.net --no-ipv6 --show-testcase --locale=da
```
```sh
zonemaster-cli zonemaster.net --no-ipv6 --show-testcase --locale=da_DK.UTF-8
```

The difference between running `zonemaster-cli` on Docker or local installation
is the invocation string, `docker run -t --rm zonemaster/cli` vs.
`zonemaster-cli`. To simplify this document, from now on the shorter
`zonemaster-cli` will be used and for Docker the longer string will be assumed.
To simplify repeated invocation on Docker an alias can be created for the shell.

To see all available command line options, use the `--help` command.

```
zonemaster-cli --help
```

## Test reports

The severity level of the different messages is CRITICAL, ERROR, WARNING, NOTICE,
INFO, DEBUG, DEBUG2 or DEBUG3. The default reporting level is NOTICE and higher.
To change the level of reporting you can use a command line option, e.g
`--level=INFO` includes level INFO and higher in the report. See
"[Severity Level Definitions]" for more information on the levels.

By default the output is formatted as plain text in English (or some other
language), but other more "technical" output formats are also available with
options `--raw` and `json`, respectively.


## Translation

### In Docker

By default all messages are in English. By using the `--locale=LANG` option
another language can be selected. Select "LANG" from the table below to have
Zonemaster translated into that language.

LANG | Language
-----|---------
da   | Danish
en   | English
fi   | Finnish
fr   | French
nb   | Norwegian
es   | Spanish
sv   | Swedish

E.g.:
```sh
docker run -t --rm zonemaster/cli zonemaster.net --locale=da
```

An alternative is to set the `LC_ALL` environment variable with correct language
value when the command is invoked, which can be useful if a shell alias is
created. E.g.
```sh
docker run -e LC_ALL=da -t --rm zonemaster/cli zonemaster.net
```

### In local installation

By default all messages are in the language set in the local environment (if
available in Zonemaster) or else in English. By using the `--locale=LOCALE`
option another language can be selected. Select "LOCALE" from the table below to
have Zonemaster translated into that language.

LOCALE      | Language
------------|---------
da_DK.UTF-8 | Danish
en_US.UTF-8 | English
fi_FI.UTF-8 | Finnish
fr_FR.UTF-8 | French
nb_NO.UTF-8 | Norwegian
es-CL.UTF-8 | Spanish
sv_SE.UTF-8 | Swedish

E.g.:
```sh
docker run -t --rm zonemaster/cli zonemaster.net --locale=da_DK.UTF-8
```

If the environment variable `LANGUAGE` is set with correct LOCALE then no option
is needed, e.g. `LANGUAGE=da_DK.UTF-8`. `zonemaster-cli` also respects `LC_ALL`,
`LC_MESSAGES` and `LANG`. `LANGUAGE` takes precedence over the other, and then
the order is `LC_ALL`, `LC_MESSAGES` and last `LANG`.

## Advanced use

There are some nice features available that can be of some use for advanced
users.

### Only run specific test cases

If you only want to run a specific test case rather than the whole suite of
tests, you can do that as well. E.g. test only test case [Connectivity03]:

[Connectivity03]:  https://github.com/zonemaster/zonemaster/blob/master/docs/specifications/tests/Connectivity-TP/connectivity03.md

```sh
zonemaster-cli --test Connectivity/connectivity03 example.com
```

Or all test case in the Connectivity test level:
```sh
zonemaster-cli --test Connectivity example.com
```

For more information on the available tests, you can list them right from
the command line tool:
```sh
zonemaster-cli --list_tests
```

## Undelegated test

Before you do any delegation change at the parent, either changing the NS
records, glue address records or DS records, you might want to perform a
check of your new child zone configuration so that everything you plan to
change is in order. Zonemaster can do this for you. All you have to do
is give Zonemaster all the parent data you plan to have for your new
configuration. Any DNS lookups going for the parent will instead be
answered by the data you entered. E.g.

```sh
zonemaster-cli --ns ns1.example.com/192.168.23.23 \
  --ns ns2.example.com/192.168.24.24 \
  --ds 12345,3,1,123456789abcdef67890123456789abcdef67890
```

Any number of NS records and DS records can be given multiple times.
The syntax of the NS records is name/address, and the address can be
both IPv4 and IPv6. The DS syntax is keytag,algorithm,type,digest.

You can also choose to do a undelegated test using only the new DS
record, but keep the NS records from the parent by only specifying the
DS record and no NS records on the command line.


[Get started]:                     https://www.docker.com/get-started
[Installation instruction]:        docs/Installation.md
[Severity Level Definitions]:      https://github.com/zonemaster/zonemaster/blob/master/docs/specifications/tests/SeverityLevelDefinitions.md
[Translation]:                     #Translation
