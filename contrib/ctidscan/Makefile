# contrib/ctidscan/Makefile

MODULE_big = ctidscan

EXTENSION = ctidscan

REGRESS = ctidscan

OBJS += gpvector.o
OBJS += ctidscan.o
OBJS += v_scan.o

ifdef USE_PGXS
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
else
subdir = contrib/ctidscan
top_builddir = ../..
include $(top_builddir)/src/Makefile.global
include $(top_srcdir)/contrib/contrib-global.mk
endif
