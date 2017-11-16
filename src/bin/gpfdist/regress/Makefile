top_builddir = $(shell cd ../../../.. && pwd)
include $(top_builddir)/src/Makefile.global

default: installcheck

REGRESS = exttab1 custom_format
PSQLDIR = $(prefix)/bin

installcheck: misc_test
	$(top_builddir)/src/test/regress/pg_regress --psqldir=$(PSQLDIR) $(REGRESS)

clean:
	rm -rf regression.* sql results expected

misc_test:
	make -C misc/gpfdist1
	make -C misc/gpfdist2
	make -C misc/gpfdist_end_of_line
	make -C misc/gpfdist_ssl

distclean: clean

.PHONY: clean distclean


