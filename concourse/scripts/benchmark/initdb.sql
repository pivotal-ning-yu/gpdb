create table if not exists test (
	test_id int2,
	test_name text
);

create table if not exists batch (
	batch_id int4,
	batch_branch_name text,
	batch_commit text
);

create table if not exists rawdata (
	tps float4,
	latency float4
);

create table if not exists summary (
);
