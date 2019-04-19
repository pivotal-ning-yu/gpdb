#!/usr/bin/env gnuplot -c

set terminal dumb size 120 30
set datafile separator ","
set xtics nomirror out
set ytics nomirror out
# set ylabel "tps"
# set xlabel "concurrency"
set border 3
set yrange [0:]
set title testname
plot filename \
	using "build":"tps" \
	notitle \
	axes x1y1 \
	with lines linetype 0 linewidth 0 \
	;

# vi:filetype=gnuplot:
