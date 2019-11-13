#include <stdarg.h>
#include <stddef.h>
#include <setjmp.h>
#include "cmockery.h"

#include "c.h"
#include "../bgwriter.c"
#include "postgres.h"

#define MAX_BGW_REQUESTS 5
void
init_request_queue(void)
{
	size_t size = sizeof(BgWriterShmemStruct) + sizeof(BgWriterRequest)*MAX_BGW_REQUESTS;
	BgWriterShmem = (BgWriterShmemStruct *) malloc(size);
	memset(BgWriterShmem, 0, size);
	BgWriterShmem->bgwriter_pid = 1234;
	BgWriterShmem->max_requests = MAX_BGW_REQUESTS;
	IsUnderPostmaster = true;
}

/*
 * Basic enqueue tests, including compaction upon enqueuing into a
 * full queue.
 */
void
test__ForwardFsyncRequest_enqueue(void **state)
{
	bool ret;
	int i;
	RelFileNode dummy = {1,1,1};
	init_request_queue();
	expect_value(LWLockAcquire, lockid, BgWriterCommLock);
	expect_value(LWLockAcquire, mode, LW_EXCLUSIVE);
	will_be_called(LWLockAcquire);
	expect_value(LWLockRelease, lockid, BgWriterCommLock);
	will_be_called(LWLockRelease);
	/* basic enqueue */
	ret = ForwardFsyncRequest(dummy, 1);
	assert_true(ret);
	assert_true(BgWriterShmem->num_requests == 1);
	/* fill up the queue */
	for (i=2; i<=MAX_BGW_REQUESTS; i++)
	{
		expect_value(LWLockAcquire, lockid, BgWriterCommLock);
		expect_value(LWLockAcquire, mode, LW_EXCLUSIVE);
		will_be_called(LWLockAcquire);
		expect_value(LWLockRelease, lockid, BgWriterCommLock);
		will_be_called(LWLockRelease);
		ret = ForwardFsyncRequest(dummy, i);
		assert_true(ret);
	}
	expect_value(LWLockAcquire, lockid, BgWriterCommLock);
	expect_value(LWLockAcquire, mode, LW_EXCLUSIVE);
	will_be_called(LWLockAcquire);
	expect_value(LWLockRelease, lockid, BgWriterCommLock);
	will_be_called(LWLockRelease);
#ifdef USE_ASSERT_CHECKING
	expect_value(LWLockHeldByMe, lockid, BgWriterCommLock);
	will_return(LWLockHeldByMe, true);
#endif
	/*
	 * This enqueue request should trigger compaction but no
	 * duplicates are in the queue.  So the queue should remain
	 * full.
	 */
	ret = ForwardFsyncRequest(dummy, 0);
	assert_false(ret);
	assert_true(BgWriterShmem->num_requests == BgWriterShmem->max_requests);
	free(BgWriterShmem);
}

int
main(int argc, char* argv[]) {
	cmockery_parse_arguments(argc, argv);
	MemoryContextInit();
	const UnitTest tests[] = {
		unit_test(test__ForwardFsyncRequest_enqueue)
	};
	return run_tests(tests);
}
