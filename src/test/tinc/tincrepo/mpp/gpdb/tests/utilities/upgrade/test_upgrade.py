"""
Copyright (C) 2004-2015 Pivotal Software, Inc. All rights reserved.

This program and the accompanying materials are made available under
the terms of the under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
"""

import os

import tinctest
from tinctest.lib import gpplatform
from tinctest.models.scenario import ScenarioTestCase

from gpdb_upgrade  import UpgradeTestCase
import mpp.gpdb.tests.utilities.upgrade as upgrade


class UpgradeScenarioTestCase(ScenarioTestCase, UpgradeTestCase):

    def __init__(self, methodName):
        super(UpgradeScenarioTestCase, self).__init__(methodName)

    def setUp(self):
        self.upgrade_from = os.environ.get('UPGRADE_FROM', '4.2.6.0 2 sp')
        self.binary_swap_from = os.environ.get('BINARY_SWAP_FROM', '4.3.4.1 2 sp')
        if 'binary_swap' in self.test_method:
            (self.old_gpdb, self.new_gpdb) = self.get_gpdbpath_info(self.binary_swap_from)
        else:
            (self.old_gpdb, self.new_gpdb) = self.get_gpdbpath_info(self.upgrade_from)
        self.db_port = self.get_master_port()
        self.db_name='gptest'
        # test_upgrade_schema_topology should use the GPDB instance
        # that we setup in install_GPDB().
        if self.test_method in ("test_upgrade_schema_topology",
                                "test_upgrade_schema_topology_mirror"):
            self.old_env = {"PGPORT": os.environ["PGPORT"],
                            "GPHOME": os.environ["GPHOME"]}
            if "PGDATABASE" in os.environ:
                self.old_env["PGDATABASE"] = os.environ["PGDATABASE"]
            os.environ["PGPORT"] = str(self.db_port)
            os.environ["PGDATABASE"] = self.db_name
            os.environ["GPHOME"] = self.old_gpdb + "/greenplum-db"
            tinctest.logger.info(
                "global environment set to:\nPGPORT=%s\nGPHOME=%s" %
                   (os.environ["PGPORT"], os.environ["GPHOME"]))


    def tearDown(self):
        self.cleanup_upgrade(self.old_gpdb, self.new_gpdb, self.db_port, self.test_method)
        # Restore global environment so that we don't affect other
        # tests in the suite.
        if self.test_method in ("test_upgrade_schema_topology",
                                "test_upgrade_schema_topology_mirror"):
            os.environ["PGPORT"] = self.old_env["PGPORT"]
            os.environ["GPHOME"] = self.old_env["GPHOME"]
            if "PGDATABASE" in self.old_env:
                os.environ["PGDATABASE"] = self.old_env["PGDATABASE"]
            else:
                os.environ.pop("PGDATABASE")
            tinctest.logger.info(
                "global environment restored to:\nPGPORT=%s\nGPHOME=%s" %
                   (os.environ["PGPORT"], os.environ["GPHOME"]))


    def test_upgrade_sanity_mirror(self):
        """
        @product_version gpdb: [4.3.0.0-]
        """
        test_case_list0 = []
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.install_GPDB', [self.upgrade_from]))
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.setup_upgrade', {'old_version':self.upgrade_from, 'master_port': self.db_port, 'mirror_enabled' : True}))

        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.run_workload', ['test_dir'], {'db_port': self.db_port}))
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.validate_workload', ['test_dir'], {'db_port': self.db_port}))

        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.run_migrator', [self.old_gpdb, self.new_gpdb, self.db_port], {'mirror_enabled' : True}))
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.validate_upgrade_correctness', [self.new_gpdb, self.db_port, self.test_method]))

        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.validate_workload', ['test_dir'], {'db_port': self.db_port, 'use_diff_ans_file': True}))
        self.test_case_scenario.append(test_case_list0, serial=True)


    def test_upgrade_sanity_perfmon(self):
        """
        @product_version gpdb: [4.3.0.0-]
        """

        test_case_list0 = []
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.install_GPDB', [self.upgrade_from]))
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.setup_upgrade', {'old_version':self.upgrade_from, 'master_port': self.db_port, 'mirror_enabled' : True}))

        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.run_workload', ['test_dir'], {'db_port': self.db_port}))
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.validate_workload', ['test_dir'], {'db_port': self.db_port}))

        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.run_migrator', [self.old_gpdb, self.new_gpdb, self.db_port], {'mirror_enabled' : 'True', 'enable_perfmon' : True}))
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.validate_upgrade_correctness', [self.new_gpdb, self.db_port, self.test_method]))
        
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.validate_workload', ['test_dir'], {'db_port': self.db_port, 'use_diff_ans_file': True}))
        self.test_case_scenario.append(test_case_list0, serial=True)

    def upgrade_with_schema_topology(self, mirror_enabled=True):

        test_case_list0 = []
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.install_GPDB', [self.upgrade_from]))
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.setup_upgrade', {'old_version':self.upgrade_from, 'master_port':self.db_port, 'mirror_enabled':mirror_enabled}))
        self.test_case_scenario.append(test_case_list0, serial=True)

        with upgrade.NewEnv(MASTER_DATA_DIRECTORY= self.old_gpdb + '/master/gpseg-1',
                             PGPORT=str(self.db_port),
                             GPHOME= self.old_gpdb + '/greenplum-db',
                             PGDATABASE=self.db_name) as env:
            classlist = []
            classlist.append('mpp.gpdb.tests.catalog.schema_topology.test_ST_DMLOverJoinsTest.DMLOverJoinsTest')
            classlist.append('mpp.gpdb.tests.catalog.schema_topology.test_ST_OSSpecificSQLsTest.OSSpecificSQLsTest')
            classlist.append('mpp.gpdb.tests.catalog.schema_topology.test_ST_AllSQLsTest.AllSQLsTest')
            if mirror_enabled:
                classlist.append('mpp.gpdb.tests.catalog.schema_topology.test_ST_GPFilespaceTablespaceTest.GPFilespaceTablespaceTest')
            self.test_case_scenario.append(classlist , serial=True)

        test_case_list1 = []
        test_case_list1.append(('.gpdb_upgrade.UpgradeTestCase.run_migrator', [self.old_gpdb, self.new_gpdb, self.db_port], {'mirror_enabled' : mirror_enabled}))
        test_case_list1.append(('.gpdb_upgrade.UpgradeTestCase.validate_upgrade_correctness', [self.new_gpdb, self.db_port, self.test_method]))
        self.test_case_scenario.append(test_case_list1, serial=True)

    def test_upgrade_schema_topology(self):
        self.upgrade_with_schema_topology(mirror_enabled=False)
    
    def test_upgrade_schema_topology_mirror(self):
        self.upgrade_with_schema_topology(mirror_enabled=True)
    
    def upgrade_mirror_with_fault_injection(self, fault_num, mirror_enabled):
        bin_platform = gpplatform.get_info()

        if bin_platform.find("RHEL") != -1:
            test_case_list0 = []
            test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.install_GPDB', [self.upgrade_from]))
            test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.setup_upgrade', {'old_version':self.upgrade_from, 'master_port': self.db_port, 'mirror_enabled' : mirror_enabled}))

            test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.run_migrator', [self.old_gpdb, self.new_gpdb, self.db_port], {'mirror_enabled' : mirror_enabled, 'expected_error_string': "[CRITICAL]:-faultinjection=%s" % fault_num, 'migrator_option': "--fault-injection=%s" % fault_num}))
            test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.validate_upgrade_correctness', [self.new_gpdb, self.db_port, self.test_method]))
            self.test_case_scenario.append(test_case_list0, serial=True)


    def test_upgrade_mirror_fault_injection_1(self):
        self.upgrade_mirror_with_fault_injection(1, mirror_enabled=True)

    def test_upgrade_mirror_fault_injection_9(self):
        self.upgrade_mirror_with_fault_injection(9, mirror_enabled=False)

    def test_upgrade_mirror_fault_injection_10(self):
        if self.get_product_version()[1].find("4.2") == 0:
            self.skipTest("Skipping due to MPP-16385")
        self.upgrade_mirror_with_fault_injection(10, mirror_enabled= False)

    def test_upgrade_mirror_with_standby(self):
        """
        @product_version gpdb: [4.3.0.0-]
        """
        test_case_list0 = []
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.install_GPDB', [self.upgrade_from]))
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.setup_upgrade', {'old_version':self.upgrade_from, 'master_port': self.db_port, 'mirror_enabled' : True}))

        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.run_workload', ['test_dir'], {'db_port': self.db_port}))
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.validate_workload', ['test_dir'], {'db_port': self.db_port}))

        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.run_migrator', [self.old_gpdb, self.new_gpdb, self.db_port], {'mirror_enabled' : True}))
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.validate_upgrade_correctness', [self.new_gpdb, self.db_port, self.test_method]))

        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.validate_workload', ['test_dir'], {'db_port': self.db_port, 'use_diff_ans_file': True}))

        test_case_list0.append(('mpp.gpdb.tests.utilities.upgrade.UpgradeHelperClass.create_standby', [self.old_gpdb, self.new_gpdb, self.db_port]))

        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.run_workload', ['walrep_dir'],  {'db_port': self.db_port}))
        self.test_case_scenario.append(test_case_list0, serial=True)


    def test_backup_restore_with_upgrade(self):
        
        test_case_list0 = []
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.install_GPDB', [self.upgrade_from]))
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.setup_upgrade', {'old_version':self.upgrade_from, 'master_port': self.db_port, 'mirror_enabled' : True}))

        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.run_workload', ['bkup_dir'], {'db_port': self.db_port}))

        test_case_list0.append(('mpp.gpdb.tests.utilities.upgrade.UpgradeHelperClass.backup_db',[self.old_gpdb,self.db_port, 'bkdb']))
        
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.run_migrator', [self.old_gpdb, self.new_gpdb, self.db_port], {'mirror_enabled' : True}))
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.validate_upgrade_correctness', [self.new_gpdb, self.db_port, self.test_method]))

        test_case_list0.append(('mpp.gpdb.tests.utilities.upgrade.UpgradeHelperClass.restore_db',[self.old_gpdb, self.new_gpdb, self.db_port, 'bkdb']))

        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.run_workload', ['bkup_dir'], {'db_port': self.db_port}))
        self.test_case_scenario.append(test_case_list0, serial=True)

    def test_upgrade_43x_binary_swap(self):
        """
        @product_version gpdb: [4.3.0.0- 4.3.99.99]
        """
        self.assertTrue( self.binary_swap_from.find('4.3') !=-1 ,"Invalid BINARY_SWAP_FROM version for 43x binary swap")

        test_case_list0 = []
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.install_GPDB', [self.binary_swap_from]))

        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.setup_upgrade', {'old_version':self.binary_swap_from, 'master_port': self.db_port, 'mirror_enabled' : True}))
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.create_filespaces', [self.db_port]))
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.run_workload', ['test_objects'], {'db_port': self.db_port}))
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.run_workload', ['test_dir'], {'db_port': self.db_port}))

        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.run_workload', ['test_dir_43x'], {'db_port': self.db_port, 'output_to_file': True}))
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.modify_sql_and_ans_files', ['ao', 'test_dir_43x']))
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.modify_sql_and_ans_files', ['aoco', 'test_dir_43x']))

        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.validate_workload', ['test_dir'], {'db_port': self.db_port, 'binary_swap':True}))

        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.run_swap',[self.old_gpdb, self.new_gpdb, self.db_port]))

        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.validate_workload', ['test_dir'], {'db_port': self.db_port, 'binary_swap':True}))
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.validate_workload', ['test_dir_43x'], {'db_port': self.db_port}))
        self.test_case_scenario.append(test_case_list0, serial=True)


    def test_upgrade_catalog_no_workload(self):
        
        test_case_list0 = []
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.setup_upgrade', { 'old_version':self.upgrade_from, 'master_port': self.db_port, 'mirror_enabled' : True, 'fresh_db': True}))
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.run_workload', ['test_catalog'], {'db_port': self.db_port, 'prefix' : "validate_", 'output_to_file' : True }))

        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.cleanup_upgrade', [self.old_gpdb, self.new_gpdb, self.db_port, self.test_method], {'fresh_db' : True}))
        self.test_case_scenario.append(test_case_list0, serial=True)
        
        test_case_list1 = []
        test_case_list1.append(('.gpdb_upgrade.UpgradeTestCase.install_GPDB', [self.upgrade_from]))
        test_case_list1.append(('.gpdb_upgrade.UpgradeTestCase.setup_upgrade', {'old_version':self.upgrade_from, 'master_port': self.db_port, 'mirror_enabled' : True}))

        test_case_list1.append(('.gpdb_upgrade.UpgradeTestCase.run_migrator', [self.old_gpdb, self.new_gpdb, self.db_port], {'mirror_enabled' : True}))
        test_case_list1.append(('.gpdb_upgrade.UpgradeTestCase.validate_upgrade_correctness', [self.new_gpdb, self.db_port, self.test_method]))

        test_case_list1.append(('.gpdb_upgrade.UpgradeTestCase.validate_workload', ['test_catalog'], {'db_port': self.db_port}))
        self.test_case_scenario.append(test_case_list1, serial=True)

   
    def upgrade_with_workload(self, schema_topology_dir):
       
        test_case_list0 = []
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.setup_upgrade', { 'old_version':self.upgrade_from, 'master_port': self.db_port, 'mirror_enabled' : True, 'fresh_db': True}))

        mdd = self.upgrade_home + '/gpdb_%s/' % self.get_product_version()[1] + 'master/gpseg-1'
        test_case_list0.append(('mpp.gpdb.tests.utilities.upgrade.UpgradeHelperClass.create_filespace',['cdbfast_fs_sch1', mdd, self.db_port, self.new_gpdb]))
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.run_workload', [schema_topology_dir], {'db_port': self.db_port,  'output_to_file' : True}))

        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.run_workload', ['catalog_sql'], {'db_port': self.db_port, 'prefix' : "validate_", 'output_to_file' : True }))

        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.cleanup_upgrade', [self.old_gpdb, self.new_gpdb, self.db_port, self.test_method], {'fresh_db' : True}))
        self.test_case_scenario.append(test_case_list0, serial=True)
        
        test_case_list1 = []
        test_case_list1.append(('.gpdb_upgrade.UpgradeTestCase.install_GPDB', [self.upgrade_from]))
        test_case_list1.append(('.gpdb_upgrade.UpgradeTestCase.setup_upgrade', {'old_version':self.upgrade_from, 'master_port': self.db_port, 'mirror_enabled' : True}))

        mdd = self.old_gpdb + '/master/gpseg-1'
        test_case_list1.append(('mpp.gpdb.tests.utilities.upgrade.UpgradeHelperClass.create_filespace',['cdbfast_fs_sch1', mdd, self.db_port, self.old_gpdb + '/greenplum-db/']))
        test_case_list1.append(('.gpdb_upgrade.UpgradeTestCase.run_workload', [schema_topology_dir], {'db_port': self.db_port}))

        test_case_list1.append(('.gpdb_upgrade.UpgradeTestCase.run_migrator', [self.old_gpdb, self.new_gpdb, self.db_port], {'mirror_enabled' : True}))
        test_case_list1.append(('.gpdb_upgrade.UpgradeTestCase.validate_upgrade_correctness', [self.new_gpdb, self.db_port, self.test_method]))

        test_case_list1.append(('.gpdb_upgrade.UpgradeTestCase.validate_workload', ['catalog_sql'], {'db_port': self.db_port, 'if_assert' : False}))
        test_case_list1.append(('.gpdb_upgrade.UpgradeTestCase.verify_diff_files', ['catalog_sql']))

        self.test_case_scenario.append(test_case_list1, serial=True)
        
    def test_upgrade_with_workload_43(self):
        """
        @product_version gpdb: [4.3.0.0- 4.3.99.99]
        """
        self.upgrade_with_workload('schema_topology_42')

    def test_rollback_with_symlink(self):
        """
        @product_version gpdb: [4.3.6.2-4.3.9.0]
        """
        fault_num = 1
        test_case_list0 = []
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.install_GPDB', [self.upgrade_from]))
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.setup_upgrade', {'old_version':self.upgrade_from, 'master_port': self.db_port, 'mirror_enabled' : True}))
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.create_symlink_dir_in_mdd', {'src': os.path.join(self.old_gpdb, 'master', 'gpseg-1', 'some_dir'), 'dst': os.path.join(self.old_gpdb, 'master', 'gpseg-1', 'symlink_dir')}))
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.run_migrator', [self.old_gpdb, self.new_gpdb, self.db_port], {'mirror_enabled' : True, 'expected_error_string': "[CRITICAL]:-faultinjection=%s" % fault_num, 'migrator_option': "--fault-injection=%s" % fault_num}))
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.validate_upgrade_correctness', [self.new_gpdb, self.db_port, self.test_method]))
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.remove_symlink_dir_in_mdd', {'symlink': os.path.join(self.old_gpdb, 'master', 'gpseg-1', 'symlink_dir')}))
        self.test_case_scenario.append(test_case_list0, serial=True)

    def test_resume_upgrade(self):
        """
        @product_version gpdb: [4.3.6.2-4.3.9.0]
        """
        fault_num = 3
        test_case_list0 = []
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.install_GPDB', [self.upgrade_from]))
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.setup_upgrade', {'old_version':self.upgrade_from, 'master_port': self.db_port, 'mirror_enabled' : True}))
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.run_migrator', [self.old_gpdb, self.new_gpdb, self.db_port], {'mirror_enabled' : True, 'expected_error_string': "[CRITICAL]:-faultinjection=%s" % fault_num, 'migrator_option': "--fault-injection=%s" % fault_num, 'expected_output_string': 'Continuing with previous upgrade', 'resume_upgrade':'Y\\n'}))
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.validate_upgrade_correctness', [self.new_gpdb, self.db_port, self.test_method, False]))
        self.test_case_scenario.append(test_case_list0, serial=True)

    def test_restart_upgrade(self):
        """
        @product_version gpdb: [4.3.6.2-4.3.9.0]
        """
        fault_num = 3
        test_case_list0 = []
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.install_GPDB', [self.upgrade_from]))
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.setup_upgrade', {'old_version':self.upgrade_from, 'master_port': self.db_port, 'mirror_enabled' : True}))
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.run_migrator', [self.old_gpdb, self.new_gpdb, self.db_port], {'mirror_enabled' : True, 'expected_error_string': "[CRITICAL]:-faultinjection=%s" % fault_num, 'migrator_option': "--fault-injection=%s" % fault_num, 'expected_output_string': 'Restarting upgrade process', 'resume_upgrade':'N\\n'}))
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.validate_upgrade_correctness', [self.new_gpdb, self.db_port, self.test_method]))
        self.test_case_scenario.append(test_case_list0, serial=True)
