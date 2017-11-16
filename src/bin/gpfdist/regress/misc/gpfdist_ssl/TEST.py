#!/usr/bin/env python
'''
gpfdist_ssl
'''

"""
@author: Yael Paz (yael.paz@emc.com)

@description: Tests for gpfdist with SSL feature.

@copyright: Copyright (c) 2012 EMC Corporation All Rights Reserved
This software is protected, without limitation, by copyright law
and international treaties. Use of this software and the intellectual
property contained therein is expressly limited to the terms and
conditions of the License Agreement under which it is provided by
or on behalf of EMC.
"""

############################################################################
# Set up some globals, and import gptest 
#    [YOU DO NOT NEED TO CHANGE THESE]

import sys, os, string, signal, socket, subprocess, time, fileinput, re, platform
import unittest

MYD = os.environ['MYD'] = os.path.abspath(os.path.dirname(__file__))
UPD = os.environ['UPD'] = os.path.abspath(os.path.join(MYD,'..'))
if UPD not in sys.path:
    sys.path.append(UPD)
from time import sleep
from lib.gpfdist_test import * 

#from util.network import networkfrom GPFDIST import gpfdist
if platform.system() in ['Windows', 'Microsoft']:    
    remove_command = "del"
    copy_command = 'copy'
    rename_command = 'rename'
    gpload_command = 'gpload.py'
    create_empty_file = 'echo. > '
else:
    remove_command = "rm -rf"
    copy_command = 'cp -r'
    rename_command = 'mv'
    gpload_command = 'gpload'
    create_empty_file = 'touch'

def windows_path(command):
    if platform.system() in ['Windows', 'Microsoft']:
        string = ''
        for line in command:
            line = line.replace("/","\\")
            string += str(re.sub('\n','',line))
        return string
    else:
        return command


def get_hostname(local = ''):
    if platform.system() in ['Windows', 'Microsoft']:
        return '0.0.0.0'
    else:
        return str(socket.gethostbyname(socket.gethostname()))

def modify_sql_file(filename, hostport):
    file = mkpath(filename+".sql")
    if os.path.isfile(file):
        for line in fileinput.FileInput(file,inplace=1):
            if line.find("gpfdist")>=0 and hostport.find(":")>=0:
                line = re.sub('(\d+)\.(\d+)\.(\d+)\.(\d+)\:(\d+)',hostport, line)
            print str(re.sub('\n','',line))
    file2 = mkpath(filename+".ans")
    if os.path.isfile(file2):
        for line in fileinput.FileInput(file2,inplace=1):
            if line.find("gpfdist")>=0 and hostport.find(":")>=0:
                line = re.sub('(\d+)\.(\d+)\.(\d+)\.(\d+)\:(\d+)',hostport, line)
            print str(re.sub('\n','',line))

def setup_ssl_certs():
    """
    Create a new certificate based on the hostname's IP
    @note: this rewrites the data/certificate directory
    """
    os.chdir(MYD + "/data")
    cmd = "bash %s/data/setup_cert_env.sh" % (MYD)
    run(cmd)
    os.chdir(MYD)

def copy_client_certs():
    """
    Copy all client certificates to segment data directory
    @note: scp do $PGDATA rewrites to gpfdists_temp
    """
    masterDataDir = os.environ.get('MASTER_DATA_DIRECTORY')
    cc, ret = run("ls -d %s/../../dbfast?/demo*" % (masterDataDir))
    for dir in string.split(ret[0]):
        dir = dir.strip()
        cmd = "rm -rf %s/gpfdists" % dir
        run(cmd)
        cmd = "cp -f -r %s/data/certificate/gpfdists %s/gpfdists 2>&1" % (MYD, dir)
        run(cmd)

###########################################################################
#  A Test class must inherit from unittest.TestCase
#    [CREATE A CLASS FOR YOUR TESTS]

class gpfdist_ssl(unittest.TestCase):

    def setUp(self):
        pass
    
    def tearDown(self):
        pass

    def check_result(self,ifile, optionalFlags = "", outputPath = ""):
        """
        PURPOSE: compare the actual and expected output files and report an
            error if they don't match.
        PARAMETERS:
            ifile: the name of the .sql file whose actual and expected outputs
                we want to compare.  You may include the path as well as the
                filename.  This function will process this file name to
                figure out the proper names of the .out and .ans files.
            optionalFlags: command-line options (if any) for diff.
                For example, pass " -B " (with the blank spaces) to ignore
                blank lines.
        """
        f1 = outFile(ifile, outputPath=outputPath)
        f2 = gpdbAnsFile(ifile)

        result = isFileEqual(f1, f2, optionalFlags, outputPath=outputPath)
        self.failUnless(result)

        return True

    def doTest(self, num, start_gpfdist = True, options = False, comment = False, modify_sql = True, filename='query', ssl=None):
        prefix = '%s%d' % (filename,num)
        run("cp -f %s.* test/" % (prefix))
        filename = mkpath("test", filename)

        if modify_sql:
            modify_sql_file(filename+str(num), host+':'+str(port1))
        if not comment:
            comment = ''
        if ssl is None:
            ssl = '%s/data/certificate/server'  % MYD
        elif ssl is False:
            ssl = None

        if not start_gpfdist:
            file = mkpath('%s%d.sql' % (filename,num))
            runfile(file,comment)
        else:
            os.chdir(MYD)
            run_gpfdist('-d %s/.. --ssl %s' % (MYD, ssl), port1) 
            run_gpfdist('-d %s/.. --ssl %s' % (MYD, ssl), port2) 
            file = mkpath('%s%d.sql' % (filename,num))
            runfile(file,comment)
            killall('gpfdist')
        self.check_result(file)

######################################################################################################################################################

    def test_00_ssl_setup(self): 
        "gpfdist ssl: setup"
        run("rm -rf test")
        run("mkdir test") 
        setup_ssl_certs()
        copy_client_certs()
        file = mkpath('setup.sql')
        runfile(file)

    def test_01_ssl_create_RET_with_SSL(self):
        "gpfdist ssl1: create RET with SSL  "
        self.doTest(1,True)

      
    def test_02_ssl_create_WET_with_SSL(self):
        "gpfdist ssl2: create WET with SSL "
        subprocess.Popen(['ssh', host, '('+remove_command+' '+MYD+'/data/tbl2.tbl)'])
        subprocess.Popen(['ssh', host, '('+create_empty_file+' '+MYD+'/data/tbl2.tbl)'])
        self.doTest(2,True)
 
    def test_03_server_and_client_certifcate_dont_match(self):
        "gpfdist ssl3: server and client certifcate don't match "
        ssl = MYD+"/data/certificate/server_wrong/"
        self.doTest(3,True,ssl=ssl)
 
    def test_05_ssl_2_ETL_server(self):
        "gpfdist ssl5: use at 2 ETL servers  "
        # @note: All regression run has 2 segment, modifying the test
        self.doTest(5)

    def test_06_ssl_using_gpfdist_instead_gpfdists(self):
        "gpfdist ssl6: run gpfdist process with ssl & create RET using gpfdist instead gpfdists "
        self.doTest(6,True)

    def test_07_ssl_run_ETL_without_SSL(self):
        "gpfdist ssl7: run gpfdist process on ETL server without adding --ssl and certificates directory path  "
        self.doTest(7, ssl=False)

    def test_08_ssl_select_RET_100_times(self):
        "gpfdist ssl8: select RET that include SSL - 100 times "
        ssl = '%s/data/certificate/server'  % MYD   
        run_gpfdist('-d %s/.. --ssl %s' % (MYD, ssl), port1)
        modify_sql_file("query8",host+':'+str(port1))
        runfile(mkpath("query8.sql"))
        file = mkpath("query8a.sql")
        runfile(file)
        self.check_result(file)
        killall('gpfdist')

    def test_09_ssl_YAML_file_with_SSL(self):
        "gpfdist ssl9: using YAML file"
        f = open(MYD+'/data/ssl.yml','w')
        f.write("version: 1.0.0.1")
        f.write("\ndatabase:  "+DBNAME)
        f.write("\nUSER: "+os.environ.get('USER'))
        f.write("\nhost: "+get_hostname()+"")
        f.write("\nport: "+get_port())
        f.write("\ngpload:")
        f.write("\n    input:")
        f.write("\n          - source:")
        f.write("\n              local_hostname:")
        f.write("\n                -  "+get_hostname('true')+"\n")         
        f.write("\n              file: ")
        f.write("\n                - "+MYD+"/data/tbl1.tbl")
        f.write("\n              ssl: true ")
        f.write("\n              CERTIFICATES_PATH: "+MYD+"/data/certificate/server/")
        f.write("\n          - columns:")
        f.write("\n              - s1: text")
        f.write("\n              - s2: text")
        f.write("\n              - s3: text")
        f.write("\n              - dt: timestamp")
        f.write("\n              - n1: smallint")
        f.write("\n              - n2: integer")
        f.write("\n              - n3: bigint")
        f.write("\n              - n4: decimal")
        f.write("\n              - n5: numeric")
        f.write("\n              - n6: real")
        f.write("\n              - n7: double precision")
        f.write("\n          - delimiter: '|'")
        f.write("\n          - format: text")
        f.write("\n          - MAX_LINE_LENGTH: 268435456")
        f.write("\n    output:")
        f.write("\n          - table: public.tbl_item")
        f.write("\n          - MODE: insert")
        f.write("\n")
        f.close()         

        f2 = open(MYD+'/query9.sql','w')
        f2.write('\!'+gpload_command+' -f '+MYD+'/data/ssl.yml')
        f2.close()
        self.doTest(9)
         
    def test_10_ssl_create_RET_using_gpfdist_and_gpfdists(self):
        "gpfdist ssl10: run gpfdist process with ssl & create RET using gpfdist & gpfdists "
        self.doTest(10,True)

    def test_11_ssl_create_RET_using_gpfdist_and_gpfdists(self):
        "gpfdist ssl11: run gpfdist process without ssl & create RET using gpfdist & gpfdists "
        self.doTest(11)

    # There is no tbl11_6GB.tbl in data folder, skip test
    def DONTtest_12_ssl_using_big_file(self):
        "gpfdist ssl12: select RET with SSL - and using a big data table"
        self.doTest(12,True)
    
    def test_999_ssl_cleanup(self):
        "gpfdist ssl999: cleanup"
        file = mkpath('cleanup.sql')
        runfile(file)

###########################################################################
#  Try to run if user launched this script directly
#     [YOU SHOULD NOT CHANGE THIS]
if __name__ == '__main__':
    suite = unittest.TestLoader().loadTestsFromTestCase(gpfdist_ssl)
    runner = unittest.TextTestRunner(verbosity=2)
    ret = not runner.run(suite).wasSuccessful()
    sys.exit(ret)
