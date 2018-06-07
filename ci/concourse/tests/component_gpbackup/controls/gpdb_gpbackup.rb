# encoding: utf-8

title 'Greenplum Backup integration testing'

control 'gpbackup rpm: files bundled' do
  impact 1.0
  title 'All binaries are present after installation'

  describe file("/usr/local/greenplum-db-#{ENV['GPDB_VERSION']}/bin/gpbackup") do
    it { should exist }
  end

  describe file("/usr/local/greenplum-db-#{ENV['GPDB_VERSION']}/bin/gpbackup_helper") do
    it { should exist }
  end

  describe file("/usr/local/greenplum-db-#{ENV['GPDB_VERSION']}/bin/gprestore") do
    it { should exist }
  end

  describe file("/usr/local/greenplum-db-#{ENV['GPDB_VERSION']}/bin/gpbackup_s3_plugin") do
    it { should exist }
  end

  describe file("/usr/local/greenplum-db-#{ENV['GPDB_VERSION']}/bin/gpbackup_ddboost_plugin") do
    it { should exist }
  end

end
