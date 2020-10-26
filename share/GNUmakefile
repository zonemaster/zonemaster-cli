# This is the main Makefile in this directory and should be kept
# GNU Make compatible.

.POSIX:
.SUFFIXES: .po .mo
.PHONY: all dist touch-po update-po extract-pot

DISTNAME = Zonemaster-CLI
POFILES := $(shell find . -maxdepth 1 -type f -name '*.po' -exec basename {} \;)
MOFILES := $(POFILES:%.po=%.mo)
POTFILE = $(DISTNAME).pot
PMFILES := $(shell find ../lib -type f -name '*.pm' | sort)

all: $(MOFILES)
	@echo
	@echo Remember to make sure all of the above names are in the
	@echo MANIFEST file, or they will not be installed.
	@echo

touch-po:
	@touch $(POTFILE) $(POFILES)

update-po: extract-pot $(POFILES)

extract-pot:
	@xgettext --output $(POTFILE) --sort-by-file --add-comments --language=Perl --from-code=UTF-8 -k__ -k\$$__ -k%__ -k__x -k__n:1,2 -k__nx:1,2 -k__xn:1,2 -kN__ -kN__n:1,2 -k__p:1c,2 -k__np:1c,2,3 -kN__p:1c,2 -kN__np:1c,2,3 $(PMFILES)

$(POTFILE): extract-pot

%.po: $(POTFILE)
	@msgmerge --update --backup=none --quiet --no-location $(MSGMERGE_OPTS) $@ $(POTFILE)

.po.mo:
	@msgfmt -o $@ $<
	@mkdir -p locale/`basename $@ .mo`/LC_MESSAGES
	@ln -vf $@ locale/`basename $@ .mo`/LC_MESSAGES/$(DISTNAME).mo

show-fuzzy:
	@for f in $(POFILES) ; do msgattrib --only-fuzzy $$f ; done