subdir=src/backend/utils/time
top_builddir=../../../../..
include $(top_builddir)/src/Makefile.global

TARGETS=tqual

include $(top_builddir)/src/backend/mock.mk

tqual.t: \
	$(MOCK_DIR)/backend/storage/ipc/shmem_mock.o
