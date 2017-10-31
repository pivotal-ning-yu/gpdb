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

import inspect
import os
import platform
import re
import shutil
import sys
import socket
import stat
import time
import datetime
import zipfile
import tinctest
import pexpect as pexpect

from gppylib.commands.base import Command, REMOTE, ExecutionError
from gppylib.db import dbconn
from gppylib.db.dbconn import UnexpectedRowsError

from tinctest import logger
from tinctest.lib import local_path, Gpdiff, run_shell_command
from tinctest.lib import gpplatform
from tinctest.lib.gpinitsystem import gpinitsystem
from tinctest.lib.system import TINCSystem

from mpp.models import MPPTestCase
from mpp.lib.PSQL import PSQL
from mpp.lib.gprecoverseg import GpRecover
from mpp.lib.gpfilespace import Gpfilespace

from tinctest.runner import TINCTextTestResult

# ==============================================================================
class UpgradeTestCase(MPPTestCase):
    """
        Base class for an upgrade test case
    """
    RC_BUILD_PROD_LINK = "http://artifacts-cache.ci.eng.pivotal.io"

    def __init__(self, methodName, rc_build_prod_link = RC_BUILD_PROD_LINK):
        self.test_method = methodName

        self.rc_build_prod_link = rc_build_prod_link
        self.db_port = '10300'
        self.upgraded_version = ''
        self.mirror_enabled = False
        self.db_name = 'gptest'
        self.upgrade_home = os.path.dirname(sys.modules[self.__class__.__module__].__file__)
        self.mirror_port_base = "50000" 
        self.rep_port_base = "41000"
        self.mirror_rep_port_base = "51000"
        self.master_port = 10300
        self.masterhost = socket.gethostname()
        self.transforms = {"%PORT_BASE%":"40000",
                           "%MASTER_HOST%":self.masterhost,
                           "%HOSTFILE%":self.upgrade_home +\
                           "/hostfile_gpinitsystem"}
        self.bin_platform = gpplatform.build_info()
        super(UpgradeTestCase, self).__init__(methodName)

    def install_GPDB(self, gp_version, gpdb_download_link=None):
        """
        @param gp_version: the name of the gpdb to install
        @type  gp_version: String
        @param gpdb_download_link: the url to download the gpdb binary. If
                                       it's not given the default one will be generated
        @type  gpdb_download_link: String
        """
        ver_list = gp_version.split(" ")
        gpdb_version = ver_list.pop(0)
        logger.debug("Starting the install for GPDB version %s" % gpdb_version)

        install_dir = self.copy_binaries(gpdb_version, ver_list.pop(0))
        logger.debug("GPDB Install Dir %s " % install_dir)
        old_gphome_path = self.unzip_download_and_install(install_dir)

    def get_gpdbpath_info(self, old_version, new_version=None):
        """
        @param old_version : the name of the gpdb upgrading from
        @param new_version : the name of the gpdb upgrading to
        """
        target_dir = "%s/gpdb_%s/" % (self.upgrade_home, old_version.split(" ").pop(0))        
        old_gpdb_path = target_dir
        if new_version:
            target_dir = "%s/gpdb_%s/" % (self.upgrade_home, new_version.split(" ").pop(0))
            new_gpdb_path = target_dir
        else:
            new_gpdb_path = os.environ.get('GPHOME')
        return old_gpdb_path, new_gpdb_path

    def unzip_download_and_install(self, target_dir):
        """
        @param install_dir: the url to install the gpdb binary
        @type  install_dir: String
        @return: the location of the gpdb
        @rtype : String
        """
        logger.debug("Untar binaries ...")
        for file in os.listdir(target_dir):
            if file.endswith(".zip"):
                zip = zipfile.ZipFile(target_dir + "/" + file)
                zip.extractall(target_dir)
                os.remove(target_dir + "/" + file)
                break
        if zip is None:
            logger.info("Downloading fails. No zip file!")
            raise Exception("Downloading fails. No zip file!")
        for file in os.listdir(target_dir):
            if file.endswith(".bin"):
                os.chmod(target_dir + "/" + file, 0777)
                break
        if file is None:
            logger.info("Unzipping fails. No bin file!")
            raise Exception("Unzipping fails. No bin file!")

        logger.debug("Running installer ...")
        installer = "/bin/sh %s" % (target_dir + "/" + file)
        child = pexpect.spawn(installer)
        check = child.expect(['.*You must read and accept.*', ' '], timeout=600)
        if check != 0:
            logger.error("Error: No text in license agreement.")
            sys.exit(1)

        #Escape out of the more session displaying the license
        child.sendline('q')
        
        #Accept the installer license
        child.sendline('yes')

        #Installation path output
        child.expect ('\r\n\*{80}\r\n.+\r\n\*{80}\r\n')
        
        #Provide the install path, override the default install path
        install_dir = target_dir + '/greenplum'
        child.sendline(install_dir)
        child.expect ('\r\n\*{80}\r\n.+\r\n\*{80}\r\n')

        #Accept the install path we just provided
        child.sendline('yes')
        child.expect ('\r\n\*{80}\r\n.+\r\n\*{80}\r\n')        

        #The path does not exist, have the installer create the install path
        child.sendline('yes')

        # Handle GPpkg upgrade optional prompt
        index = child.expect (['\r\n\*{80}\r\n\[Optional\].+\r\n\*{80}\r\n',
                               'Extracting'])
        if index == 0:
            child.sendline('')
            child.expect('Extracting')

        # Verify the completion of the installation
        child.expect ('\r\n\*{80}\r\nInstallation\scomplete.+\r\n\*{80}\r\n')

        #Installer is done, close child and log
        child.close()
        logger.debug("Finished running the installer ...")
        version_chck_cmd = install_dir + "/bin/gpstart --version"
        cmd = Command(name='version check', cmdStr=version_chck_cmd, ctxt=REMOTE, remoteHost='localhost')
        cmd.run(validateAfter=True)
        result = cmd.get_results().stdout
        logger.debug("Installed version - %s"%result)
        for file in os.listdir(target_dir):
            if file.endswith(".tar.gz"):
                shutil.move(target_dir+'/'+file, install_dir)
                save_path = os.getcwd()
                os.chdir(install_dir)
                res = {'rc':0, 'stderr':'', 'stdout':''}
                run_shell_command ('tar -xzf %s' % file, 'untar qautils', res)
                if res['rc'] > 0:
                    raise Exception('Unable to untar Qautilities')
                os.chdir(save_path)
        return install_dir 

    def copy_binaries(self, version, build_num):
        """
        Set environment variable GPDB_INSTALLER_DIR to location of Greenplum installer

        Note: QAUtils is not needed at the moment so it is not considered here.
        """

        cur_dir = self.upgrade_home
        target_dir = "%s/gpdb_%s/" % (cur_dir, version)
        logger.debug("Copying binaries over to target directory: %s" % target_dir)

        gpdb_filename = 'greenplum-db-%s-build-%s-%s.zip' % (version, build_num, self.bin_platform)
        gpdb_installer_dir = os.environ.get('GPDB_COPY_BIN_FROM', '/tmp')

        if not os.path.isdir(target_dir):
            os.mkdir(target_dir)

        shutil.copy('%s/%s' % (gpdb_installer_dir, gpdb_filename), target_dir)

        return target_dir

    def config_multi_nodes(self, seg_hosts, seg_num, testcase_init_file_location, master_host='localhost'):
        """
        @TODO : Currently not working or called from anywhere
        @param seg_host: list of the segment host names
        @type  seg_host: [String]
        @param seg_num : the number of the segments on one host
        @type  seg_num : int
        @param testcase_init_file_location: the location of the gpdb init configuration file
        @type  testcase_init_file_location: String
        @param master_host: the name of master host, default to be localhost
        @type  master_host: String
        """
        with open(self.old_gpdb_path + '/hosts','w') as f:
            f.write(platform.node() + '\n');
            for host in seg_hosts:
                f.write(host + '\n')

        newlines = []
        dict = {'MACHINE_LIST_FILE'         : self.old_gpdb_path + 'hosts',
                'declare -a DATA_DIRECTORY' : '(' + (self.old_gpdb_path + 'primary ') * seg_num + ')'}

        if self.mirror_enabled:
            dict['declare -a MIRROR_DATA_DIRECTORY'] = '(' + (self.old_gpdb_path + 'mirror ') * seg_num + ')'
                                                              
        with open(testcase_init_file_location,'r') as f:
            for line in f.readlines():
                newlines.append(self._replace_with_dict(line, dict))


        with open(testcase_init_file_location, 'w') as f:
            for line in newlines:
                f.write(line)

    def _replace_with_dict(self, str, d):
        """
        @param str: the string needs to be replaced
        @type  str: String
        @param d  : A dictionary, key is the name and value is the new value in the property file
        @type  d  : {String : String}
        @return   : the updated String
        @rtype    : String
        """
        for key, value in d.items():
           if str.startswith(key) or str.startswith('#'+key):
               return key + '=' + value + '\n'
        return str

    def _gp_segment_install(self, gp_path):
        """
        @TODO : Need for multinode config. currently not used
        @param gp_path: the gpdb location
        @type  gp_apth: String
        """
        cmd = Command(name='run gpseginstall',
                      cmdStr='source %s; gpssh-exkeys -f %s; gpseginstall -f %s -u %s' %\
                      (gp_path, self.old_gpdb_path + 'hosts', self.old_gpdb_path + 'hosts', os.getlogin()), 
                      ctxt=REMOTE, remoteHost='localhost')
        cmd.run()
        result = cmd.get_results()
        if result.rc != 0 and result.rc != 1:
            msg = "" 
            if result.stdout:
                msg += result.stdout
                msg += " "
            if result.stderr:
                msg += result.stderr
            raise Exception("gpseginstall failed (%d): %s" % (result.rc, msg))
        logger.debug("Successfully ran gpseginstall ...")

    # When providing an existing set of installed binaries, both old and new locations should be provided
    def setup_upgrade(self, old_gpdb_path=None, new_gpdb_path=None, old_version=None, mirror_enabled=False,
                      seg_num=1, seg_hosts=None, master_port=None, fresh_db=False):
        """
        @param old_gpdb_path: the local of the old gpdb
        @type  old_gpdb_path: String
        @param new_gpdb_path: the local of the new gpdb
        @type  new_gpdb_path: String
        @param old_version: the version of the old gpdb
        @type  old_version: String
        @param new_version: the version of the new gpdb
        @type  new_version: String
        @param mirror_enabled: doing upgrade with mirror or not
        @type  mirror_enabled: Boolean
        @param seg_num: the number of the segments
        @type  seg_num: int
        @param seg_hosts: list of the host name for multi-node installation
        @type  seg_hosts: [String]
        @param master_port: master port
        @type master_port: int
        @param fresh_db: Initialize a db with the upgrade_to version
        @type fresh_db: Boolean
        """

        logger.debug("Setting up environment for upgrade ... ")
        logger.debug (self.upgrade_home)

        (old_gpdb_path, new_gpdb_path) = self.get_gpdbpath_info(old_version)
        new_version = self.get_product_version()[1]
        if fresh_db:
            gphome_path = os.environ.get('GPHOME')
            gpdb_path = self.upgrade_home + '/gpdb_%s/' % new_version
            TINCSystem.make_dirs(gpdb_path)
        else:
            gphome_path = old_gpdb_path + '/greenplum-db'
            gpdb_path = old_gpdb_path
        logger.debug('Gphome: ' + gphome_path + ' Gpdb path : ' + gpdb_path)        
     
        template_init_file_location = self.upgrade_home + "/test_gpinitsystem_config_file"
        testcase_init_file_location = gpdb_path + "/gpinitsystem_config"
        tinctest.logger.info( 'testcase_init_file_location : ' + testcase_init_file_location)
        self._perform_transformation(template_init_file_location,
                                     testcase_init_file_location, gpdb_path, master_port, mirror_enabled)
        gpdbinit = gpinitsystem(gphome_path, testcase_init_file_location, gpdb_path, mirror_enabled)
        gpdbinit.run()

    def create_filespaces(self, master_port):
        #config = GPDBConfig(master_port)
        gpfile = Gpfilespace(port=master_port)
        gpfile.create_filespace('regressionfs1')
        gpfile.create_filespace('regressionfs2')
        gpfile.create_filespace('regression_fs_a')
        gpfile.create_filespace('regression_fs_b')
        gpfile.create_filespace('regression_fs_c')

    def run_workload(self, workload_dir, db_port, prefix="load_", output_to_file=False, ext=".ans", db_name=None):
        """
        Run all the load SQL files in the directory provided
        @param workload_dir: the location of the workload folder
        @type  workload)dir: String
        @param dbport: port of the gpdb cluster to connect
        @param db_name: dbname to connect to

        """
        logger.debug("Running workload ...")
        if not db_name:
            db_name= self.db_name
        load_path = self.upgrade_home + "/" + workload_dir + "/"
        if workload_dir =='catalog_sql':
            sql_file = load_path + 'setup.sql'
            docstring = self._read_metadata_as_docstring(sql_file)
            assert PSQL.run_sql_file(sql_file=sql_file, dbname = db_name,port = db_port,output_to_file =False)
        for file in os.listdir(load_path):
            if file.endswith(".sql") and file.startswith(prefix):
                sql_file = load_path + file
                docstring = self._read_metadata_as_docstring(sql_file)
                if output_to_file is False:
                    assert PSQL.run_sql_file(sql_file = load_path + file,
                                             dbname = db_name,
                                             port = db_port,
                                             output_to_file = False)
                else:
                    out_file = file.replace(".sql", ext)
                    assert PSQL.run_sql_file(sql_file = load_path + file,
                                             dbname = db_name,
                                             port = db_port,
                                             out_file = load_path + out_file,
                                             output_to_file = True)

    def validate_workload(self, workload_dir, db_port, use_diff_ans_file=False, db_name=None, binary_swap= False, if_assert=True):
        """
        Validate that the workload were executed successfully
        @param workload_dir: the location of the workload folder
        @type  workload_dir: String
        @param use_diff_ans_file: diff the ans file and the out file or not
        @type  use_diff_ans_file: Boolean
        @param db_name: Name of database to connect
        @type db_name: string
        @param binary_swap : True of False
        @param if_assert: assert the result from gpdiff
        @type if_assert: Boolean
        """
        logger.debug("Validating workload ...")
        if not db_name:
            db_name= self.db_name
        load_path = self.upgrade_home + "/" + workload_dir + "/"
        if workload_dir =='catalog_sql':
            sql_file = load_path + 'setup.sql'
            docstring = self._read_metadata_as_docstring(sql_file)
            assert PSQL.run_sql_file(sql_file=sql_file, dbname = db_name,port = db_port,output_to_file =False)
        for file in os.listdir(load_path):
            if file.endswith(".sql") and file.startswith("validate_"):
                sql_file = os.path.join(load_path, file)
                out_file = os.path.join(load_path, file.replace('.sql', '.out'))
                docstring = self._read_metadata_as_docstring(sql_file)
                assert PSQL.run_sql_file(sql_file = sql_file,
                                         port = db_port, dbname = db_name,
                                         out_file = out_file)
                
        for file in os.listdir(load_path):
            if file.endswith(".out"):
                out_file = file
                # Take care of instances when the ans file could be different post upgrade
                if use_diff_ans_file:
                    ans_file = file.replace('.out', '.ans.post')
                    if not os.path.exists(load_path + ans_file):
                        ans_file = file.replace('.out', '.ans')
                else:
                    if binary_swap:
                        if  '4.3' in self.get_product_version()[1]:
                            ans_file = file.replace('.out','.ans.43x')
                            if not os.path.exists(load_path + ans_file):
                                ans_file = file.replace('.out', '.ans')
                    else:
                        ans_file = file.replace('.out', '.ans')
                logger.debug("Ans file path - %s"%(load_path+ans_file))
                logger.debug("Ans file exists - %s"%os.path.exists(load_path + ans_file))
                
                init_file = os.path.join(load_path , 'init_file')
                
                if os.path.exists(load_path + ans_file):
                    if os.path.exists(init_file):
                        if if_assert:
                            assert Gpdiff.are_files_equal(load_path + out_file,
                                                            load_path + ans_file,  match_sub =[init_file])
                        else:
                            Gpdiff.are_files_equal(load_path + out_file,
                                                      load_path + ans_file,  match_sub =[init_file])
                    else:
                        if if_assert:
                            assert Gpdiff.are_files_equal(load_path + out_file,
                                                            load_path + ans_file)
                        else:
                            Gpdiff.are_files_equal(load_path + out_file,
                                                  load_path + ans_file)
                        
                # Ans file does not exist for validation; therefore, fail the validation
                else:
                    logger.error("There is no .ans file for the workload validation !!!")
                    assert False

    def enable_perfmon(self, old_gphome_path, mdd, db_port, passwd = '111111'):
        """
        @param passwd: the init password for the gpdb perfmon
        @type  passwd: String
        """
        cmd = Command (name = 'enable_perfmon',
                       cmdStr = 'export MASTER_DATA_DIRECTORY=%s;\
                                 export PGPORT=%s;\
                                 source %s;\
                                 gpperfmon_install --enable --password %s --port %s;\
                                 gpstop -ar;'
                                 % (mdd , db_port,
                                    old_gphome_path + '/greenplum_path.sh', passwd, db_port),
                       ctxt=REMOTE, remoteHost='localhost')
        logger.debug("Installing perfmon now ...")
        cmd.run ()
        result = cmd.get_results ()
        if result.rc != 0:
            msg = "" 
            if result.stdout:
                msg += result.stdout
                msg += " "
            if result.stderr:
                msg += result.stderr
            raise Exception("Install perfmon failed (%d): %s" % (result.rc, msg))
        logger.debug("Successfully install perfmon")
        

    
        
    def run_migrator(self, old_gpdb, new_gpdb, master_port, expected_error_string=None, enable_perfmon=False, migrator_option=None, mirror_enabled=False, expected_output_string=None, resume_upgrade=''):
        """
        Run an upgrade based on the directories passed in
        @param expected_error_string: the expected words in the error message which is used as the key words of negative test
        @type  expected_error_string: String
        @param enable_perfmon: running gpinitsystem with perfmon or not
        @type  enable_perfmon: Boolean
        """
        logger.debug("Run gpmigrator ... " )

        old_gphome_path = old_gpdb + '/greenplum-db'
        new_gphome_path = new_gpdb 
        mdd = old_gpdb + 'master/gpseg-1'

        # Install perfmon
        if enable_perfmon:
            self.enable_perfmon (old_gphome_path, mdd, master_port)

        old_dir_source = old_gphome_path + '/greenplum_path.sh'
        new_dir_source = new_gphome_path + '/greenplum_path.sh'
        gpmigrator_cmd = 'gpmigrator'
        if mirror_enabled:
            gpmigrator_cmd = 'gpmigrator_mirror'
        cmd_str = 'export MASTER_DATA_DIRECTORY=%s; \
                                   export PGPORT=%s; \
                                   source %s; \
                                   gpstop -a; \
                                   source %s; \
                                   %s %s %s ' \
                                   % (mdd , master_port, old_dir_source,
                                      new_dir_source, gpmigrator_cmd, old_gphome_path,
                                      new_gphome_path)
        if migrator_option is not None and migrator_option.startswith("--fault-injection"):
            cmd_str_fault = cmd_str + " " + migrator_option
            cmd = Command (name='run migrator with fault',
                           cmdStr=cmd_str_fault,
                           ctxt=REMOTE, remoteHost='localhost')
            logger.info('command with fault option' + cmd_str_fault)
            cmd.run()
            result = cmd.get_results()
            logger.info(result)
            if result.rc != 0:
                msg = ""
                if result.stdout:
                    msg += result.stdout
                    msg += " "
                if result.stderr:
                    msg += result.stderr
                if not (expected_error_string and expected_error_string in msg):
                    raise Exception("gpmigrator failed (%d): %s" % (result.rc, msg))

            # At this point, the gpmigrator would have run recoverseg.
            # We need to wait till segments come into sync before we do
            # proceed further. But first we need to check if the database
            # is up or down.
            if os.path.exists(os.path.join(mdd, 'postmaster.pid')):
                GpRecover().wait_till_insync_transition()
            
            expected_error_string = None
            cmd_str = 'export MASTER_DATA_DIRECTORY=%s;\
                                   export PGPORT=%s;\
                                   source %s;\
                                   gpstop -a;\
                                   gpstart -a;\
                                   sleep 60;\
                                   gpstop -a;\
                                   source %s;\
                                   echo -e "%s" | %s %s %s'\
                                   % (mdd , master_port, old_dir_source,
                                      new_dir_source, resume_upgrade, gpmigrator_cmd, old_gphome_path,
                                      new_gphome_path)
            cmd = Command (name='re-run migrator post fault',
                           cmdStr=cmd_str,
                           ctxt=REMOTE, remoteHost='localhost')
            
            logger.info('command without' + cmd_str)
            cmd.run()
            result = cmd.get_results()
            logger.info(result)
            msg = ""
            if result.stdout:
                msg += result.stdout
                msg += " "
            if result.stderr:
                msg += result.stderr
            if result.rc != 0:
                if not (expected_error_string and expected_error_string in msg):
                    raise Exception("gpmigrator failed (%d): %s" % (result.rc, msg))
            else:
                if expected_output_string and not (expected_output_string in msg):
                    raise Exception('Expected to find string "%s" in output: %s' % (expected_output_string, msg))
        else:
            if migrator_option is not None:
                cmd_str += ' ' + migrator_option
            cmd = Command (name ='configure enviroment',
                           cmdStr = cmd_str,
                           ctxt = REMOTE, remoteHost = 'localhost')
            cmd.run()

            result = cmd.get_results()
            tinctest.logger.info(result)
            msg = ""
            if result.stdout:
                msg += result.stdout
                msg += " "
            if result.stderr:
                msg += result.stderr
            if result.rc != 0:
                if not (expected_error_string and expected_error_string in msg):
                    raise Exception("gpmigrator failed (%d): %s" % (result.rc, msg))
            else:
                if expected_output_string and not (expected_output_string in msg):
                    raise Exception('Expected to find string "%s" in output: %s' % (expected_output_string, msg))

        logger.debug("Successfully migrated the greenplum database")

    def run_swap(self, old_gpdb, new_gpdb, master_port, expected_error_string=None, enable_perfmon=False, mdd=None,swap_back=False):
        
        """
        @param expected_error_string: the expected words in the error message which is used as the key words of negative test
        @type  expected_error_string: String
        @param enable_perfmon: doing binary swap with perfmon or not
        @type  enable_pergmon: Boolean
        Run an upgrade based on the directories passed in
        """
        
        logger.debug("Start binary swap ...")

        if swap_back:
            old_gphome_path = old_gpdb
            new_gphome_path = new_gpdb + '/greenplum-db'
        else:
            old_gphome_path = old_gpdb + '/greenplum-db'
            new_gphome_path = new_gpdb 
        if not mdd:
            mdd = old_gpdb + 'master/gpseg-1'

        # Install perfmon
        if enable_perfmon:
            self.enable_perfmon (old_gphome_path, mdd, master_port)

        old_dir_source = old_gphome_path + '/greenplum_path.sh'
        new_dir_source = new_gphome_path + '/greenplum_path.sh'
        cmd = Command (name='configure enviroment',
                       cmdStr='export MASTER_DATA_DIRECTORY=%s;\
                               export PGPORT=%s;\
                               source %s;\
                               gpstop -ai;\
                               source %s; gpstart -a; gpstart --version'\
                               % (mdd, master_port,
                                  old_dir_source, new_dir_source),
                       ctxt=REMOTE, remoteHost='localhost')
        logger.debug(cmd.cmdStr)
        cmd.run()

        result = cmd.get_results()
        logger.debug(result)
        if result.rc != 0:
            msg = "" 
            if result.stdout:
                msg += result.stdout
                msg += " "
            if result.stderr:
                msg += result.stderr
            if not (expected_error_string and expected_error_string in msg):
                raise Exception("Binary Swap failed (%d): %s" % (result.rc, msg))
        logger.debug("Successfully swap binary for the greenplum database")


    def validate_upgrade_correctness(self, new_gphome, db_port, test_method, check_version=True):
        if check_version:
            assert self.check_upgraded_version(db_port)
        assert self.check_cluster_state_post_upgrade()
        assert self.gpcheckcat_validation(new_gphome, test_method, db_port)

    def cleanup_upgrade(self, old_gpdb, new_gpdb, db_port, test_method, gpstop_only = False, delete_binaries = True, fresh_db = False):

        """
        Depending on if the gpstop_only boolean is set, this function will stop the upgraded cluster 
        ( so that ports are available ) or it will delete the cluster and remove the generated 
        directories for the gpdb binaries
        @note: gpdeletesystem return code is non-zero, since we have warnings. Remove the validate.
        We should check GPDB is not running (using pg_ctl) and no lock files instead of the return code.
        @param gpstop_only: only running gpstop without remove the file or not
        @type  gpstop_only: Boolean
        """
        logger.debug("Cleaning up the upgrade setup ...")
        if fresh_db:
            new_version = self.get_product_version()[1]
            gpdb_path = self.upgrade_home + '/gpdb_%s/'  % new_version
            mdd = gpdb_path + 'master/gpseg-1'
        else:
            gpdb_path = old_gpdb
            mdd = old_gpdb + 'master/gpseg-1'
        new_dir_source = new_gpdb + '/greenplum_path.sh'
        list_results = sys.exc_info()
        if list_results != (None, None, None):
            Command("backup gpdb data dirs for failed tests", "cp -rf %s %s/gpdb_%s" % (gpdb_path, self.upgrade_home, test_method)).run()
        if gpstop_only :
            cmd = Command(name='run gpstop for cleanup',
                          cmdStr='export MASTER_DATA_DIRECTORY=%s;\
                                  export PGPORT=%s;\
                                  source %s;gpstop -a'\
                                  % (mdd, db_port, new_dir_source),
                          ctxt=REMOTE, remoteHost='localhost')
            logger.debug(cmd.cmdStr)
            cmd.run(validateAfter = True)
        else :
            cmd = Command(name="test log dir", cmdStr="test -d %s/pg_log" % mdd,
                          ctxt=REMOTE, remoteHost="localhost")
            cmd.run(validateAfter=False)
            if cmd.get_results().wasSuccessful():
                dirname = datetime.datetime.fromtimestamp(time.time()).strftime('%Y-%m-%d-%H%M%S')
                os.mkdir('/tmp/%s' % dirname)
                cmdStr = "cp %s/pg_log/* /tmp/%s" % (mdd, dirname)
                cmd = Command(name='copy master logs', cmdStr=cmdStr,
                              ctxt=REMOTE, remoteHost='localhost')
                logger.debug(cmd.cmdStr)
                cmd.run(validateAfter=True)
            else:
                logger.debug("directory %s/pg_log does not exist" % mdd)

            gpdeletesystem_str = "echo -e \"y\\ny\\n\" | gpdeletesystem -d %s -f" % (mdd)
            cmd = Command(name='run gpdeletesystem for cleanup',
                          cmdStr='export MASTER_DATA_DIRECTORY=%s;\
                                  export PGPORT=%s;\
                                  source %s; %s'\
                                  % (mdd, db_port, new_dir_source,
                                     gpdeletesystem_str),
                          ctxt=REMOTE, remoteHost='localhost')

            logger.debug(cmd.cmdStr)
            cmd.run(validateAfter = False)
        if delete_binaries:
            logger.debug("Force delete GPDB binaries ...")
            cmd = Command(name='run rm GPDB binaries',
                          cmdStr='rm -rf %s'\
                              % (gpdb_path),
                          ctxt=REMOTE, remoteHost='localhost')
            cmd.run(validateAfter = True)

    def check_upgraded_version(self, db_port):
        """
        Check that the gpdb version post upgrade is correct
        @return: upgrade version check meet the requirement or not
        @rtype : Boolean
        """
        logger.debug("Checking gpdb version post upgrade ...")
        version_str = ""
        with dbconn.connect(dbconn.DbURL(dbname="template1", port = db_port )) as conn:
            query = "select * from version()"
            row = dbconn.execSQLForSingleton(conn, query)
            version_str = row.split(" ").pop(4)
        upgraded_version = self.get_product_version()[1]
        # Not sure if this is still needed whether any brnach uses '_'
        if '_' in version_str:
            version_str = version_str[:version_str.index('_')]
        if '_' in upgraded_version:
            upgraded_version = upgraded_version[:upgraded_version.index('_')]
        logger.debug( 'version_str: ' + version_str + 'upgraded_version : ' + upgraded_version)
        return version_str == upgraded_version


    def check_cluster_state_post_upgrade(self):
        """
        Post upgrade make sure that no segments are down
        @return: upgrade cluster state post check reuslt meet the expected or not
        @rtype : Boolean
        """
        logger.debug("Checking that all segments are up post upgrade ...")
        with dbconn.connect(dbconn.DbURL(dbname="template1", port = self.db_port)) as conn:
            query = "select status from gp_segment_configuration"
            rows = dbconn.execSQL(conn, query)
            for row in rows:
                if row[0].strip() != 'u':
                    return False
        return True

    def gpcheckcat_validation(self, new_gphome, test_method, db_port):
        """
        Validate that there are no inconsistencies in the catalog
        True if there are no inconsistencies 
        False otherwise
        @return: chech the updated gpdb mmeeting the new version or not
        @rtype : Boolean
                     
        """
        logger.debug("Running gpcheckcat to validate catalog ...")

        # Fetch the count of databases using gpcheckcat that pass the catalog check test
        out_file = '%s/%s_gpcheckcat.out' % (self.upgrade_home, test_method)
        cmd_str = 'source %s/greenplum_path.sh; %s/bin/lib/gpcheckcat -A -O -p %s &> %s' % (new_gphome, new_gphome, db_port, out_file)
        cmd = Command('run gpcheckcat', cmd_str)
        cmd.run(validateAfter=True)

        line_no = 0
        with open(out_file) as fp:
            for line in fp:
                if 'Found no catalog issue' in line:
                    line_no += 1

        count_db = 0
        row = 0
        # fetch the database count on the host using pg_catalog 
        with dbconn.connect(dbconn.DbURL(dbname="template1", port = db_port )) as conn:
            query = "select count(*) from pg_database"
            row = dbconn.execSQLForSingleton(conn, query)

        # -1 because gpcheckcat does not run against template0
        count_db = row - 1

        # Check if the numbers match else expansion dint go through fine return false
        if line_no != count_db:
            return False
        return True

    def get_master_port(self):
        try:
            cmd_str = "fuser -an tcp %s" % self.master_port
            cmd = Command("check port", cmd_str)
            logger.debug("checking if port available: '%s'" % cmd_str)
            cmd.run(validateAfter=True)
            raise Exception(
                "port %s already in use, details: %s" %
                (self.master_port, cmd.get_results().printResult()))
        except ExecutionError:
            # fuser retruns non-zero exit code if no process having
            # the specified tcp port open was found.
            logger.info("master port value => %s" % self.master_port)
            return self.master_port

    def _perform_transformation(self, input_filename, output_filename, old_gpdb_path, master_port, mirror_enabled, gpdb_fresh_folder=None):
 
        self.transforms.update({"%MASTER_PORT%":"%s"% master_port})
        
        if mirror_enabled:
            self.transforms.update({"%MIRROR_DIR%":old_gpdb_path + "mirror", "%MIRROR_PORT_BASE%":self.mirror_port_base, 
                                    "%REP_PORT_BASE%":self.rep_port_base, "%MIRROR_REP_PORT_BASE%":self.mirror_rep_port_base})
        if gpdb_fresh_folder == None:
            self.transforms.update({"%DATA_DIR%":old_gpdb_path + "primary",
                    "%MASTER_DATA_DIR%":old_gpdb_path + "master"})
        else:
            self.transforms.update({"%DATA_DIR%":gpdb_fresh_folder + "primary",
                    "%MASTER_DATA_DIR%":gpdb_fresh_folder + "master"})

        with open(input_filename, 'r') as input:
            with open(output_filename, 'w') as output:
                for line in input.readlines():
                    for key, value in self.transforms.iteritems():
                        if key in line:
                            line = line.replace(key, value)
                            write = True
                            break
                        elif "%" not in line:
                            write = True
                            break
                        else:
                            write = False
                    if write == True:
                        output.write(line)    
        return output_filename

    def perform_transformation_on_sqlfile(self,input_filename, output_filename,transforms):
        with open(input_filename, 'r') as input:
            with open(output_filename, 'w') as output:
                for line in input.readlines():
                    for key,value in transforms.iteritems():
                        line = re.sub(key,value,line)
                    output.write(line)
 
    def modify_sql_and_ans_files(self, ans_file_type, workload_dir):
        load_path = self.upgrade_home + "/" + workload_dir + "/"
        cmd = "select b.relid, visimaprelid, visimapidxid from pg_class a , pg_appendonly b where a.oid = b.relid and a.relname = '%s_4_3';" %ans_file_type
        ao_table_fields = PSQL.run_sql_command(cmd,port = self.db_port, dbname = self.db_name).splitlines()[3].split('|')
        transforms = {}
        transforms.__setitem__('<RELFILENODE>',ao_table_fields[0].strip())
        transforms.__setitem__('<VISIMAPID>',ao_table_fields[1].strip())
        transforms.__setitem__('<VISIMAPIDX>',ao_table_fields[2].strip())
        self.perform_transformation_on_sqlfile(load_path + "validate_%s_visimap.ans.t" %ans_file_type,load_path + "validate_%s_visimap.ans" %ans_file_type, transforms)
        self.perform_transformation_on_sqlfile(load_path + "validate_%s_update_del.sql.t" %ans_file_type,load_path + "validate_%s_update_del.sql" %ans_file_type, transforms)
        self.perform_transformation_on_sqlfile(load_path + "validate_%s_update_del.ans.t" %ans_file_type,load_path + "validate_%s_update_del.ans" %ans_file_type, transforms)
        

    def verify_diff_files(self, workload_dir):
        """
        @description: Compare the diff lines(those starting with -) in *.diff with an expected list for that file
        """

        logger.debug("Verify the diff files ...")
        load_path = self.upgrade_home + "/" + workload_dir + "/"
        for file in os.listdir(load_path):
            if file.endswith(".diff") :
                expected_diff_version = self.get_expected_diff_version(file)
                file = load_path + file
                diff_out_list = []
                diff_expected_list = []
                # Get the diff from output
                with open(file) as fp:
                    for line in fp:
                        if line.startswith('-') and not line.startswith('---'):
                            diff_out_list.append(line)
                # Get the diff from expected
                if expected_diff_version:
                    expected_diff = 'expected_diff_%s.txt' % expected_diff_version
                else:
                    expected_diff = 'expected_diff.txt'
                tinctest.logger.debug('expected diff = %s' % expected_diff)
                with open(load_path + expected_diff) as fp:
                    for line in fp:
                        if line.find('%s' % os.path.basename(file)) > -1 :
                            diff_expected_list.append(line.split(':||:')[1])
                tinctest.logger.debug('out file list')
                tinctest.logger.debug(diff_out_list)
                tinctest.logger.debug('expected file list')
                tinctest.logger.debug(diff_expected_list)
                assert (set(diff_out_list) == set(diff_expected_list))

    def _read_metadata_as_docstring(self, sql_file):
        """  
        pull out the intended docstring from the implied sql file
        parent instantiation will conveniently look to that docstring to glean metadata.
        Assumptions: Assume that the metadata is given as comments in the sql file at the top.
        TODO: Provide this as an API at TINCTestCase level so that every class can implement
        a custom way of reading metadata. 
        """
        intended_docstring = "" 
        with open(sql_file, 'r') as f:
            for line in f:
                line = line.strip()
                if line.find('--') != 0:
                    break
                intended_docstring += line[2:].strip()
                intended_docstring += "\n" 
        return intended_docstring

    def version_check(self, docstring):
        if not docstring:
            return True
        self._parse_metadata_from_doc(docstring)
        if 'product_version' not in self._metadata:
            return True
        deployed_version = self.get_product_version()
        sql_version = _TINCProductVersionMetadata(self._metadata['product_version'])
        del self._metadata['product_version']
        tinctest.logger.debug('deployed version = %s' % str(deployed_version))
        tinctest.logger.debug('sql version = %s' % sql_version)
        return sql_version.match_product_version(deployed_version[0], deployed_version[1])

    def get_expected_diff_version(self, fname):
        version = re.search('(\d.\d.\d.\d)', fname)
        if version:
            return version.group(1)
        return None
   
    def create_symlink_dir_in_mdd(self, src, dst):
        if not os.path.exists(src):
            os.makedirs(src)
        if not os.path.exists(dst):
            os.symlink(src, dst) 
        else:
            raise Exception('%s already exists!' % dst)

    def remove_symlink_dir_in_mdd(self, symlink):
        realpath = os.readlink(symlink)
        if os.path.exists(symlink):
            os.unlink(symlink)
        if os.path.exists(realpath):
            os.removedirs(realpath)
