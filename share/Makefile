POFILES = $(wildcard *.po)
MOFILES := $(POFILES:.po=.mo)

%.mo: %.po
	@mkdir -p locale/$*/LC_MESSAGES
	@perl -e 'use Locale::Msgfmt; msgfmt({in => $$ARGV[0], out => $$ARGV[1]});' $< locale/$*/LC_MESSAGES/Zonemaster-CLI.mo

all: ${MOFILES}
