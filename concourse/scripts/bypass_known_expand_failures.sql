\pset pager off
set allow_system_table_mods to true;

-- created by gpcopy.source, gpexpand does not handle db names with special
-- characters correctly, so their tables can not be expanded.
\connect "funny copy""db'with\\quotes"
drop table if exists public.foo cascade;
