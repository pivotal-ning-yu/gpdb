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

import tinctest
import os
import unittest2 as unittest
from mpp.gpdb.tests.utilities.upgrade.gpdb_upgrade import UpgradeTestCase
from tinctest.models.scenario import ScenarioTestCase

class DeltaUpgradeTestCase(ScenarioTestCase, UpgradeTestCase):
    '''
    Additonal upgrade and backup/restore
    tests for delta compression feature.
    @product_version gpdb: [4.3.3.0-]
    '''

    def setUp(self):
        (self.old_gpdb, self.new_gpdb) = self.get_gpdbpath_info()
        self.db_port = self.get_master_port()

    def tearDown(self):
        self.cleanup_upgrade(self.old_gpdb, self.new_gpdb, self.db_port, self.test_method)

    def binary_swap_43old_to_43new(self, checksum=False):
        test_case_list0 = []
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.install_GPDB'))

        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.setup_upgrade', {'master_port': self.db_port, 'mirror_enabled' : True}))

        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.run_workload', ['test_delta'], {'db_port': self.db_port}))
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.create_filespaces', [self.db_port]))
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.run_workload', ['test_objects'], {'db_port': self.db_port}))

        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.run_swap',[self.old_gpdb, self.new_gpdb, self.db_port]))

        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.validate_workload', ['test_delta'], {'db_port': self.db_port}))

        test_case_list0.append(('mpp.gpdb.tests.utilities.upgrade.UpgradeHelperClass.check_gpfiledump', [self.old_gpdb, self.new_gpdb, self.db_port, checksum]))
        self.test_case_scenario.append(test_case_list0, serial=True)

    def test_binary_swap_43new_to_43old(self):
        test_case_list0 = []
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.install_GPDB'))

        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.setup_upgrade', {'master_port': self.db_port, 'mirror_enabled' : True, 'fresh_db': True}))

        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.run_workload', ['test_delta'], {'db_port': self.db_port}))

        mdd = self.upgrade_home + '/gpdb_%s/' % self.get_product_version()[1] + 'master/gpseg-1'
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.run_swap',[ self.new_gpdb, self.old_gpdb, self.db_port], {'mdd':mdd, 'swap_back' : True}))

        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.validate_workload', ['test_delta_back'], {'db_port': self.db_port}))
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.cleanup_upgrade', [self.new_gpdb, self.old_gpdb, self.db_port, self.test_method], {'fresh_db' : True}))
        self.test_case_scenario.append(test_case_list0, serial=True)

    def backup_43old_restore_43new(self, checksum=False):
        test_case_list0 = []
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.install_GPDB'))

        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.setup_upgrade', {'master_port': self.db_port, 'mirror_enabled' : True}))

        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.run_workload', ['test_delta'], {'db_port': self.db_port}))

        test_case_list0.append(('mpp.gpdb.tests.utilities.upgrade.UpgradeHelperClass.backup_db',[self.old_gpdb,self.db_port, 'dldb']))

        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.run_swap',[self.old_gpdb, self.new_gpdb, self.db_port]))

        test_case_list0.append(('mpp.gpdb.tests.utilities.upgrade.UpgradeHelperClass.restore_db',[self.old_gpdb, self.new_gpdb, self.db_port, 'dldb']))

        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.validate_workload', ['test_delta'], {'db_port': self.db_port}))

        test_case_list0.append(('mpp.gpdb.tests.utilities.upgrade.UpgradeHelperClass.check_gpfiledump', [self.old_gpdb, self.new_gpdb, self.db_port,checksum]))
        self.test_case_scenario.append(test_case_list0, serial=True)

    def test_binary_swap_43old_to_43new(self):
        '''
        @product_version gpdb: [4.3.3.0-4.3.3.99]
        '''
        self.binary_swap_43old_to_43new()

    def test_binary_swap_43old_to_43new(self):
        '''
        @product_version gpdb: [4.3.4.0-]
        '''
        self.binary_swap_43old_to_43new(True)

    def test_backup_43old_restore_43new(self):
        '''
        @product_version gpdb: [4.3.3.0-4.3.3.99]
        '''
        self.backup_43old_restore_43new()

    def test_backup_43old_restore_43new(self):
        '''
        @product_version gpdb: [4.3.4.0-]
        '''
        self.backup_43old_restore_43new(checksum=True)

