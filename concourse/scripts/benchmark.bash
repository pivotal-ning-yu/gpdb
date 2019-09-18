#!/bin/bash -l

set -eox pipefail

./ccp_src/scripts/setup_ssh_to_cluster.sh

HOSTNAME_MASTER=mdw
HOSTNAME_CLIENT=edw0
MASTER_DATA_DIRECTORY=/data/gpdata/master/gpseg-1
GPHOME=/usr/local/greenplum-db-devel
PGPORT=5432
SCALE=1000

# output the admin hostname of a unprivileged hostname
get_admin_hostname()
{
	local host="$1"

	grep "$host" ./cluster_env_files/etc_hostfile \
		| cut -d' ' -f3
}

# install gnuplot to generate plots
install_gnuplot() {
	local host="$1"

	ssh "$host" bash -ex <<-EOF
		sudo yum install -y \
			gnuplot
	EOF
}

setup_benchmark() {
	ssh $HOSTNAME_MASTER \
	GPHOME="$GPHOME" \
	PGPORT="$PGPORT" \
	MASTER_DATA_DIRECTORY="$MASTER_DATA_DIRECTORY" \
	SCALE="$SCALE" \
	bash -ex <<-"EOF"
		source $GPHOME/greenplum_path.sh

		# enable access from client host
		echo "host all all samenet trust" >> $MASTER_DATA_DIRECTORY/pg_hba.conf

		# enable GDD to support concurrent UPDATE/DELETE
		gpconfig -c gp_enable_global_deadlock_detector -v on
		# reduce logs for better performance
		gpconfig -c log_statement -v ddl
		# turn off orca
		gpconfig -c optimizer -v off
		# do not resend too frequently
		gpconfig -c gp_interconnect_timer_period -v 50ms
		## turn off fsync
		#gpconfig -c fsync -v off --skipvalidation
		# trigger checkpoint more frequently for better OLTP performance
		if gpconfig -s checkpoint_segments >/dev/null 2>&1; then
			gpconfig -c checkpoint_segments -v 2 --skipvalidation
		else
			gpconfig -c min_wal_size -v 2
			gpconfig -c max_wal_size -v 2
		fi
		gpstop -rai

		createdb

		# prepare benchmark dir
		mkdir /tmp/benchmark

		# install pgbench and libpq binaries
		cp $(which pgbench) /tmp/benchmark/
		cp -a $GPHOME/lib/libpq.so* /tmp/benchmark/

		# install helper scripts
		cp -a gpdb_src/concourse/scripts/benchmark /tmp/benchmark/scripts

		# substitude scale in *.sql
		sed -i "s/@scale@/$SCALE/g" /tmp/benchmark/scripts/*.sql
	EOF

	# deploy to client host
	ssh $HOSTNAME_CLIENT mkdir -p /tmp/benchmark
	ssh $HOSTNAME_MASTER tar -C /tmp/benchmark -cf - . \
		| ssh $HOSTNAME_CLIENT tar -C /tmp/benchmark -xf -
	jq -r .pipeline_url cluster_env_files/terraform*/metadata \
		| cut -d/ -f11 \
		| ssh $HOSTNAME_CLIENT tee /tmp/benchmark/version

	# install historical data
	ssh $HOSTNAME_CLIENT tar -C /tmp/benchmark -zxf - \
		< benchmark_data/benchmark_data.tar.gz
}

run_benchmark() {
	ssh $HOSTNAME_CLIENT \
	PGPORT="$PGPORT" \
	PGHOST="$HOSTNAME_MASTER" \
	MASTER_DATA_DIRECTORY="$MASTER_DATA_DIRECTORY" \
	SCALE="$SCALE" \
	bash -ex <<-"EOF"
		export LD_LIBRARY_PATH=.:$LD_LIBRARY_PATH
		T=10

		# the order is important: keep readonly tests before update tests
		TESTS=(
			begin-end
			select-only
			begin-select-end
			insert-only
			simple-update
			tpcb-like
			update-only
			begin-update-end
		)

		cd /tmp/benchmark

		./pgbench --quiet -i -s $SCALE

		for test in "${TESTS[@]}"; do
			mkdir -p "output/$test"

			for ((N = 20; N <= 200; N += 20)); do
				echo "-- test=$test scale=$SCALE T=$T N=$N"
				file="output/$test/scale${SCALE}_T${T}_N${N}.log"
				./pgbench -s $SCALE -c $N -j $N -T $T -P 1 -r \
					-f scripts/${test}.sql >$file 2>&1
				echo
			done
		done
	EOF
}

analyze_data() {
	ssh $HOSTNAME_CLIENT bash -ex <<-"EOF"
		cd /tmp/benchmark
		./scripts/convert.bash
		./scripts/plot.bash
	EOF

	# copy back historical data
	ssh $HOSTNAME_CLIENT tar -C /tmp/benchmark -zcf - benchmark_data \
		> gpdb_artifacts/benchmark_data.tar.gz
}

install_gnuplot "$(get_admin_hostname $HOSTNAME_CLIENT)"

setup_benchmark
run_benchmark

analyze_data
