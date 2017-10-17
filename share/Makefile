POFILES = $(wildcard *.po)
MOFILES := $(POFILES:.po=.mo)

MSGFMT  = msgfmt --check

%.mo: %.po
	@echo Generating locale/$*/LC_MESSAGES/Zonemaster-CLI.mo
	@mkdir -p locale/$*/LC_MESSAGES
	@${MSGFMT} -o locale/$*/LC_MESSAGES/Zonemaster-CLI.mo $<

all: ${MOFILES}
