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
import socket
import re
import tinctest
from gppylib.db import dbconn
from tinctest.lib import run_shell_command, local_path
from mpp.models import MPPTestCase
from mpp.lib.PSQL import PSQL

from mpp.gpdb.tests.storage.lib.gp_filedump import GpfileTestCase

class UpgradeHelperClass(MPPTestCase):

    def backup_db(self, old_gpdb, db_port, db_name, options=" ", new_gpdb=None, mdd=None):
        if not mdd:
            mdd = os.path.join(old_gpdb , 'master/gpseg-1')
        if new_gpdb:
            cmdStr = "export MASTER_DATA_DIRECTORY=%s; export PGPORT=%s; source %s;gpcrondump -x %s -a %s" % (mdd, db_port, new_gpdb + '/greenplum_path.sh', db_name, options)
        else:
            cmdStr = "export MASTER_DATA_DIRECTORY=%s; export PGPORT=%s; source %s;gpcrondump -x %s -a %s" % (mdd, db_port, old_gpdb + '/greenplum-db/greenplum_path.sh', db_name, options)
        res = {'rc':0, 'stderr':'', 'stdout':''}
        run_shell_command (cmdStr, 'run gpcrondump', res)
        if res['rc'] > 0:
            raise Exception("gpcrondump failed with rc %s" % res['rc'])
        return res

    def restore_db(self, old_gpdb, new_gpdb, db_port, db_name, mdd=None):
        if not mdd:
            mdd = os.path.join(old_gpdb , 'master/gpseg-1')
        cmdStr="export MASTER_DATA_DIRECTORY=%s; export PGPORT=%s;export PGDATABASE=%s;source %s;gpdbrestore -e -s %s -a" % (mdd, db_port, 'gptest',  new_gpdb + '/greenplum_path.sh', db_name)
        res = {'rc':0, 'stderr':'', 'stdout':''}
        run_shell_command (cmdStr, 'run gpdbrestore', res)
        if res['rc'] > 0:
            raise Exception("gpdbrestore failed with rc %s" % res['rc'])
        return res

    def check_gpfiledump(self, old_gpdb, new_gpdb, db_port, checksum=False):
        gpfile = GpfileTestCase()

        if checksum == True:
            flag = " -M "
        else:
            flag = " "
        mdd = old_gpdb + 'master/gpseg-1'

        os.environ["MASTER_DATA_DIRECTORY"] = mdd
        os.environ["PGPORT"] =str(db_port)
        os.environ["GPHOME"] =new_gpdb

        (host, db_path) = gpfile.get_host_and_db_path('dldb')
        file_list = gpfile.get_relfile_list('dldb', 'delta_t1', db_path, host)
        for i in range(0, len(file_list)-2): # not for the .0 node and text column
            self.assertTrue(gpfile.check_in_filedump(db_path, host, file_list[i], 'HAS_DELTA_COMPRESSION', flag) , 'Delta compression not applied to new inserts')
