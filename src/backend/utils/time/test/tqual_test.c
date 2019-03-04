#include <stdarg.h>
#include <stddef.h>
#include <setjmp.h>
#include "cmockery.h"

#include "postgres.h"
#include "utils/memutils.h"

#include "../tqual.c"

void
test_boundaries_of_CreateSharedSnapshotArray(void **state)
{
	/*
	 * max_prepared_xacts is used to calculate NUM_SHARED_SNAPSHOT_SLOTS. Make
	 * it non-zero so that we actually allocate some local snapshot slots.
	 */
	max_prepared_xacts = 2;

	SharedSnapshotStruct *fakeSharedSnapshotArray = NULL;

	Size sharedSnapshotShmemSize = SharedSnapshotShmemSize();
	fakeSharedSnapshotArray = malloc(sharedSnapshotShmemSize);

	will_return(ShmemInitStruct, fakeSharedSnapshotArray);
	will_assign_value(ShmemInitStruct, foundPtr, false);
	expect_any_count(ShmemInitStruct, name, 1);
	expect_any_count(ShmemInitStruct, size, 1);
	expect_any_count(ShmemInitStruct, foundPtr, 1);

	CreateSharedSnapshotArray();

	for (int i=0; i<sharedSnapshotArray->maxSlots; i++)
	{
		SharedSnapshotSlot *s = &sharedSnapshotArray->slots[i];

		/*
		 * Assert that every slot xip array falls inside the boundaries of the
		 * allocated shared snapshot.
		 */
		assert_true(s->snapshot.xip > fakeSharedSnapshotArray);
		assert_true(s->snapshot.xip < (((void *)fakeSharedSnapshotArray) +
												sharedSnapshotShmemSize));
	}
}

int
main(int argc, char* argv[])
{
	cmockery_parse_arguments(argc, argv);

	const UnitTest tests[] = {
		unit_test(test_boundaries_of_CreateSharedSnapshotArray)
	};
	MemoryContextInit();
	return run_tests(tests);
}
