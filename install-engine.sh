#!/bin/sh
set -ex

sudo apt update
#sudo apt install libdevel-checklib-perl
sudo apt install libldns2
cpanm Devel::CheckLib

cd /tmp
git clone https://github.com/zonemaster/zonemaster-ldns/archive
unzip zonemaster-ldns.zip
cd zonemaster-ldns-develop
perl Makefile.PL --no-internal-ldns
make
sudo make install
perl -MZonemaster::Engine -E 'say $Zonemaster::LDNS::VERSION'

cd /tmp
wget -O zonemaster-engine https://github.com/zonemaster/zonemaster-engine/archive/develop.zip
unzip zonemaster-engine.zip
cd zonemaster-engine-develop
perl Makefile.PL
make
sudo make install
perl -MZonemaster::Engine -E 'say $Zonemaster::Engine::VERSION'
