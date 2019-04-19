#!/usr/bin/env bash

version="$(cat version)"
datadir="benchmark_data/$version"
csvdir="$datadir/csv"
outdir="$datadir/output"

ln -nfs "$csvdir" csv
mkdir -p "$datadir"
cp -a output "$datadir"

# convert raw output to csv files
tests="$(cd "$outdir"; ls)"
for test in $tests; do
	mkdir -p "$csvdir/$test"

	echo '"N","tps","tps (exclude)","tps (peak)","tps (valley)","latency average","latency stddev"' \
		> "$csvdir/${test}.csv"

	files="$(cd "$outdir/$test"; ls)"
	for file in $files; do
		# format of filename: scale1000_T60_N120.log
		name=${file%.*}
		other=$name
		scale=${other%%_*}
		other=${other#*_}
		T=${other%%_*}
		other=${other#*_}
		N=${other%%_*}

		scale=${scale#scale}
		T=${T#T}
		N=${N#N}

		unset latency_avg latency_std tps_inc tps_exc

		echo '"N","tps","latency","stddev"' > "$csvdir/$test/${name}.csv"

		while read -r -a ws; do
			case "${ws[0]}" in
				progress:)
					echo "${ws[1]},${ws[3]},${ws[6]},${ws[9]}"
					;;
				latency)
					if [ "${ws[1]}" = 'average:' ]; then
						latency_avg=${ws[2]}
					else
						latency_std=${ws[2]}
					fi
					;;
				tps)
					if [ "${ws[3]}" = '(including' ]; then
						tps_inc=${ws[2]}
					else
						tps_exc=${ws[2]}
					fi
					;;
			esac
		done < "$outdir/$test/$file" >> "$csvdir/$test/${name}.csv"

		tps_max=$(tail -n+2 "$csvdir/$test/${name}.csv" \
			| cut -d, -f2 \
			| sort -gr \
			| head -n1)
		tps_min=$(tail -n+2 "$csvdir/$test/${name}.csv" \
			| cut -d, -f2 \
			| sort -g \
			| head -n1)

		echo "$N,$tps_inc,$tps_exc,$tps_max,$tps_min,$latency_avg,$latency_std"
	done | sort -g >> "$csvdir/${test}.csv"
done

# merge historical data
rm -f benchmark_data/*.csv
builds="$(cd "benchmark_data"; ls -vd */)"
for build in $builds; do
	build=${build%/}

	# rescan for test list as not every build contains the same tests
	tests="$(cd "$datadir/csv/"; ls -d */)"
	for test in $tests; do
		test=${test%/}
		# put file header when necessary
		if [ ! -e "benchmark_data/${test}.csv" ]; then
			echo '"build","N","tps","latency","stddev"' \
				> "benchmark_data/${test}.csv"
		fi

		# find out the line with max tps
		printf "%d," "$build" >> "benchmark_data/${test}.csv"
		tail -n+2 "benchmark_data/$build/csv/${test}.csv" \
			| sort -t, -rgk2 \
			| head -n1 \
			>> "benchmark_data/${test}.csv"
	done
done
