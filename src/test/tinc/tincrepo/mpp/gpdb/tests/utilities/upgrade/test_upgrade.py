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
        (self.old_gpdb, self.new_gpdb) = self.get_gpdbpath_info()
        self.db_port = self.get_master_port()
        self.db_name='gptest'

    def tearDown(self):
        self.cleanup_upgrade(self.old_gpdb, self.new_gpdb, self.db_port, self.test_method)

    def test_upgrade_43x_binary_swap(self):
        """
        @product_version gpdb: [4.3.0.0- 4.3.99.99]
        """
        test_case_list0 = []
        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.install_GPDB'))

        test_case_list0.append(('.gpdb_upgrade.UpgradeTestCase.setup_upgrade', {'master_port': self.db_port, 'mirror_enabled' : True}))
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
