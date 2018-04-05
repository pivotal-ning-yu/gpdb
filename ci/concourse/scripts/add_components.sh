#!/bin/bash

run() {
	>&2 echo "+ $@"
	"$@"
}

# Ignores args past $1, so this is useful to expand a glob to the first match.
fileExists() {
	if ! [ -f "$1" ] ; then
		1>&2 echo "File not found, or is not a file: $1"
		exit 1
	fi
	echo "$1"
}

add_component() {
	local component="$1"

	local component_tar=$(fileExists "$component"/*.tar*)
	echo "Add $component_tar"

	run mkdir "unpackaged_$component"
	run tar xzf "$component_tar" -C "./unpackaged_$component" || return 1

	export GPHOME=$PWD/unpackaged_gpdb
	( cd "unpackaged_$component" && run ./install_gpdb_component ) || return 1
}

mkdir unpackaged_gpdb
tar xf bin_gpdb/bin_gpdb.tar.gz -C unpackaged_gpdb || exit 1

for component in component_* ; do
	add_component "$component" || exit 1
done

# Some of the components may unpack files which are owned by users that
# only existed on the machine that tar'ed those files up. Here we make
# everything owned by root which should exist on any Linux system.
run chown root:root -R "unpackaged_gpdb"

(
cd unpackaged_gpdb
run tar czf ../bin_gpdb_with_components/bin_gpdb.tar.gz ./*
) || exit 1
