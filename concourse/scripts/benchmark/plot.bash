#!/usr/bin/env bash

# generate plots of current build
for file in csv/*.csv; do
	name=${file%.*}
	name=${name##*/}

	echo "~~~ $name ~~~"

	while IFS=, read -r n tps _ _ _ latency _; do
		if [ "$n" = '"N"' ]; then
			printf -- '------+------------+------------\n'
			printf '%5s |%11s |%11s\n' "N" "tps" "latency"
			printf -- '------+------------+------------\n'
		else
			printf '%5d |%11.2f |%11.2f\n' "$n" "$tps" "$latency"
		fi
	done <"$file"

	# below syntax is for backward compatiblity with gnuplot 4.x
	gnuplot -e "testname='$name'" -e "filename='$file'" scripts/plot-current.gp

	echo
done

# generate plots of historical data
for file in benchmark_data/*.csv; do
	name=${file%.*}
	name=${name##*/}

	echo "~~~ $name (historical) ~~~"

	while IFS=, read -r build n tps _ _ _ latency _; do
		if [ "$n" = '"N"' ]; then
			printf -- '-------+------+------------+------------\n'
			printf '%6s |%5s |%11s |%11s\n' \
				"build" "N" "tps" "latency"
			printf -- '-------+------+------------+------------\n'
		else
			printf '%6d |%5d |%11.2f |%11.2f\n' \
				"$build" "$n" "$tps" "$latency"
		fi
	done <"$file"

	# below syntax is for backward compatiblity with gnuplot 4.x
	gnuplot -e "testname='$name (historical)'" -e "filename='$file'" scripts/plot-historical.gp

	echo
done
