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

import os, re
import platform
import tinctest
from gppylib.commands.base import Command
from tinctest.lib import run_shell_command, local_path
from tinctest import logger

class Gppkg:
    GPPKG_URL = os.environ.get('GPPKG_RC_URL',None)

    def check_pkg_exists(self, pkgname):
        cmd = 'gppkg -q --all'
        res = {'rc':0, 'stderr':'', 'stdout':''}
        run_shell_command (cmd, 'run gppkg', res)
        logger.debug(res['stdout'])
        pkgs = res['stdout'].strip().split('\n')[1:]
        for pkg in pkgs:
            if pkgname in pkg:
                return (True, pkg)
        return (False, None)

    def run_gppkg_uninstall(self, pkgname):
        """
        @summary: Runs gppkg -r to uninstall a gppkg. Output is written to gppkg_r.log file in current directory.
        @param pkgfile: The name of the .gppkg file
        @raise GppkgUtilError: If gppkg uninstall fails
        """
        (existed, pkg) = self.check_pkg_exists(pkgname)
        if not existed:
            logger.info('the package does not exist, no need to remove, %s'%pkgname)
            return True
        logger.debug( '\nGppkgUtil: Uninstalling gppkg using gppkg file: %s' % (pkg))
        cmd = 'gppkg -r %s' % pkg
        res = {'rc':0, 'stderr':'', 'stdout':''}
        run_shell_command (cmd, 'run gppkg', res)
        logger.debug(res)
        if res['rc']> 0:
            logger.info('Failed to Uninstall the package, %s' % pkgname)
            return False
        else:
            return True

    def run_gppkg_install(self, pkgfile):
        """
        @summary: Runs gppkg -i to install a gppkg. Output is written to gppkg_i.log file in current directory.
        @param pkgdir: The directory containing the gppkg file
        @param pkgfile: The name of the .gppkg file in pkgdir
        @raise GppkgUtilError: If gppkg install fails or if pkgfile specified does not exist
        """
        if os.path.isfile(pkgfile):
            logger.debug( '\nGppkgUtil: Installing gppkg using gppkg file: %s' % (pkgfile))
            cmd = 'gppkg -i %s' % pkgfile
            res = {'rc':0, 'stderr':'', 'stdout':''}
            run_shell_command (cmd, 'run gppkg', res)
            logger.debug(res)
            if res['rc']> 0:
                tinctest.logger.info('result from install package %s' % res['stdout'])
                raise Exception('Failed to install the package')
            self.check_and_install_sql(res['stdout'])
        else:
            raise Exception("*** ERROR: .gppkg file not found '. Make sure %s exists." % (pkgfile))

    def check_and_install_sql(self, output = None):
        lines = output.strip().split('\n')
        res = {'rc':0, 'stderr':'', 'stdout':''}
        for line in lines:
            if 'Please run psql -d mydatabase -f $GPHOME' in line:
                sql_path = os.environ.get('GPHOME') + line.split('Please run psql -d mydatabase -f $GPHOME')[1].split(' ')[0]
                run_shell_command('psql -d %s -f %s' % (os.environ.get('PGDATABASE', 'gptest'), sql_path), 'run sql to build functions for the package', res)
                tinctest.logger.info('running sql file %s, result is %s' % (sql_path, res['stdout']))
                break

    def download_pkg(self, product_version, gppkg):
        """
        Download gppkg from s3.
        """
        target_dir = local_path('download/')
        if not os.path.exists(target_dir):
            os.makedirs(target_dir)
        (rc, package_name) = self.get_package_name_from_config(product_version, gppkg)
        if rc != 0:
            return -1, None, None

        compatibility_test = "orca" not in package_name

        copy_cmd = "cp /tmp/downloads/%s %s" % (package_name, os.path.join(target_dir, package_name))

        logger.debug('copy cmd: %s' % copy_cmd)

        cmd = Command("copy from expected location", copy_cmd)

        tinctest.logger.info('Executing command: %s' % (copy_cmd))
        cmd.run()
        result = cmd.get_results()
        tinctest.logger.info('Finished command execution with return code %s ' % (str(result.rc)))
        tinctest.logger.debug('stdout: ' + result.stdout)
        tinctest.logger.debug('stderr: ' + result.stderr)

        if result.rc > 0:
            raise Exception("Gppkg download failed: %s" % result.stderr)
        return 0, target_dir, package_name

    def gppkg_install(self, product_version, gppkg):
        (existed, _) = self.check_pkg_exists(gppkg)
        if existed:
            return True
        (rc, pkg_dir, pkg_name) = self.download_pkg(product_version, gppkg)
        if rc != 0:
            return False
        pkgfile = local_path(pkg_dir + pkg_name)
        self.run_gppkg_install(pkgfile)
        run_shell_command('gpstop -air')
        return True

    def get_package_name_from_config(self, product_version, gppkg):
        gpdb_version = '4.3'
        orca = ""
        try:
            minor_version = float(re.compile('.*\d+\.\d+\.(\d+\.\d+)').match(product_version).group(1))
            if minor_version >= float(5.0):  # minor version grabbed from 4.3.5.0 when orca was introduced
                orca = 'orca'
        except Exception as e:
            logger.error("%s" % str(e))
            raise Exception('Unable to parse product_version: %s' % product_version)

        os_, platform_ = self.get_os_platform()
        compatible = self.check_os_compatibility(os_, gppkg)
        if not compatible:
            logger.error("the package %s is not compatible with the os %s, please make sure the compatible package exists" %(gppkg, os_))
            return -1, None, None
        gppkg_config = self.getconfig(product_version=gpdb_version, gppkg=gppkg)
        gppkg_config['pkg'] = gppkg
        gppkg_config['gpdbversion'] = gpdb_version
        gppkg_config['os'] = self.failover_gppkg_to_os_version(os_, gppkg)
        gppkg_config['platform'] = platform_
        gppkg_config['type'] = 'gppkg'
        gppkg_config['orca'] = orca

        gppkg_name = "%(pkg)s-pv%(version)s_gpdb%(gpdbversion)s%(orca)s-%(os)s-%(platform)s.%(type)s" % gppkg_config
        if 'gpdbversion' in gppkg_config  and 'ossversion' in gppkg_config:
            gppkg_name = "%(pkg)s-ossv%(ossversion)s_pv%(version)s_gpdb%(gpdbversion)s%(orca)s-%(os)s-%(platform)s.%(type)s" % gppkg_config

        return 0, gppkg_name

    def getconfig(self, product_version='4.2', gppkg=None):
        config_file = local_path('gppkg.'+product_version+'.config')
        fd = open(config_file, 'r')
        config = ()
        for line in fd:
            if gppkg in line:
                properties = line.strip().split(":")[1]
                config = dict(item.split("=") for item in properties.split(";") if item)
        return config

    def get_os_compatiable_pkg_list(self, os_ = 'rhel5'):
        config_file = local_path('gppkg_platform.config')
        if os.path.exists(config_file):
            fd = open(config_file, 'r')
            compatiable_pkg_list = []
            for line in fd:
                if os_ in line:
                    properties = line.strip().split(":")[1]
                    [compatiable_pkg_list.append(item) for item in properties.split(",") if item]
            return compatiable_pkg_list
        else:
            raise Exception("gppkg_platform.config not found under: %s" % local_path(''))

    def get_os_platform(self):
        from sys import platform as _platform
        machine = ''
        if _platform.startswith('linux'):  # Both SuSE and RHEL returns linux, might be linux2 or linux4
            if os.path.exists("/etc/SuSE-release"):
                machine = 'suse'
            else:
                machine = 'redhat'
        elif _platform == 'sunos5':
            machine = 'solaris'

        if not machine:
            raise Exception('unable to recognize the platform. sys.platform found: %s' % _platform)

        cmd = 'cat '
        res = {'rc':0, 'stderr':'', 'stdout':''}
        os_ = "unknown"
        if machine.lower() == 'suse':
            cmd = cmd + '/etc/SuSE-release'
            run_shell_command (cmd, 'check os kernel version', res)
            if 'SUSE Linux Enterprise Server 11' in res['stdout']:
                os_ = 'suse11'
            elif 'SUSE Linux Enterprise Server 10' in res['stdout']:
                os_ = 'suse10'
        elif machine.lower() == 'redhat':
            cmd = cmd + '/etc/redhat-release'
            run_shell_command (cmd, 'check os kernel version', res)
            if 'Linux Server release 5.' in res['stdout']:
                os_ = 'rhel5'
            elif 'Linux Server release 6.' in res['stdout']:
                os_ = 'rhel6'
            # We've already confirmed it's redhat/centos with the file
            elif '6.' in res['stdout']:
                os_ = 'rhel6'
        elif machine.lower() == 'solaris':
            cmd = cmd + '/etc/release'
            run_shell_command (cmd, 'check os kernel version', res)
            if 'Solaris 10' in res['stdout']:
                os_ = 'sol10'
            elif 'Solaris 11' in res['stdout']:
                os_ = 'sol11'
        logger.debug(res['stdout'])

        return os_, platform.machine()

    def check_os_compatibility(self, os_='rhel5', pkg_name=None):
        gppkg_os_compatiable_list = self.get_os_compatiable_pkg_list(os_)
        if pkg_name not in gppkg_os_compatiable_list:
            return False
        else:
            return True

    def failover_gppkg_to_os_version(self, os_=None,  pkg_name=None):
        """ this function basically return a gppkg version which works on current platform
            except the plperl needs rhel6, rhel5, and suse10, suse11 for different platform
            others can use the suse10, rhel5 version for both platforms
        """
        if pkg_name == 'plperl':
            return os_
        else:
            if os_ == 'suse11':
                return 'suse10'
            elif os_ == 'rhel6':
                return 'rhel5'
            elif os_ == 'sol11':
                return 'sol10'
            else:
                return os_
