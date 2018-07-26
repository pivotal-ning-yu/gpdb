/*-------------------------------------------------------------------------
 *
 * nodeReshuffle.h
 *
 *
 *
 * Portions Copyright (c) 1996-2011, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 * src/include/executor/nodeReshuffle.h
 *
 *-------------------------------------------------------------------------
 */
#ifndef NODERESHUFFLE_H
#define NODERESHUFFLE_H

#include "nodes/execnodes.h"

extern TupleTableSlot *ExecReshuffle(ReshuffleState *node);
extern ReshuffleState *ExecInitReshuffle(Reshuffle *node, EState *estate, int eflags);
extern void ExecEndReshuffle(ReshuffleState *node);
extern void ExecReScanReshuffle(ReshuffleState *node);

#endif   /* NODERESHUFFLE_H */
