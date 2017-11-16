#!/usr/bin/env python
'''
gpfdist
'''

############################################################################
# Set up some globals, and import gptest 
#    [YOU DO NOT NEED TO CHANGE THESE]

import sys
import unittest
import os
import string
import signal
import socket
import subprocess
import time
import fileinput
import re

MYD = os.environ['MYD'] = os.path.abspath(os.path.dirname(__file__))
UPD = os.environ['UPD'] = os.path.abspath(os.path.join(MYD,'..'))
if UPD not in sys.path:
    sys.path.append(UPD)
from time import sleep
from lib.gpfdist_test import * 

def modify_sql_file(filename, port=8080):
    replace_str(filename,"sql",port)
    replace_str(filename,"ans",port)
    if filename in ['query21']:
        replace_str(filename,"ans.orca",port)

def replace_str(filename,ext="sql",port=8080):
    file = mkpath(filename+"." + ext)
    dir, f = os.path.split(filename)
    two_gpfdist_tests=['query49','query51']
    
    if f in two_gpfdist_tests:
       # if IPv6 else IPv4
       if host.find(":")>=0:
               ip1 = "[%s]:%s" % (host,port1)
               ip2 = "[%s]:%s" % (host,port2)
       else:
               ip1=host+":"+str(port1)
               ip2=host+":"+str(port2)
       ctr=0
       ip = ip1
       for line in fileinput.FileInput(file,inplace=1):
                line2 = re.sub('(\d+)\.(\d+)\.(\d+)\.(\d+)', ip, line)
                if line2 != line:
                     ip = ip2
                line = line2
                print str(re.sub('\n','',line))

       return
    if f in 'query21':
        ## get number of segments
        rc, ret = run("psql template1 -t -c \"select count(*) from gp_segment_configuration where role = 'p' and content != -1;\"")
        if not rc:
            print "cant get number of segments"
            sys.exit(rc)
        num_segments = int(ret[0]) #config.getNPrimarySegments()
        base_ext_file_url = "'gpfdist://10.1.2.16/gpfdist2/data/lineitem%s.tbl'"
        external_files_urls_list = []
        for num in xrange(0, num_segments+1):
            if num == 0:
                external_files_urls_list.append(base_ext_file_url % '')
            else:
                external_files_urls_list.append(base_ext_file_url % str(num))
        external_files_urls = ',\n        '.join(external_files_urls_list)
        found_message = 'Found %d URLs and %d primary segments' % (num_segments + 1, num_segments)
            
        ## fill in external files urls
        for line in fileinput.FileInput(file,inplace=1):
            if '%EXTERNAL_FILES_URLS%' in line:
                print re.sub('%EXTERNAL_FILES_URLS%', external_files_urls, line).rstrip('\n')
            elif '%FOUND_MESSAGE%' in line:
                line2 = re.sub('%FOUND_MESSAGE%', found_message, line)
                print str(re.sub('\n','',line2))
            else:
                print str(re.sub('\n','',line))
    if os.path.isfile(file):
        for line in fileinput.FileInput(file,inplace=1):
            # gpfdist://[ipv6]:8080
            if line.find("gpfdist")>=0 and host.find(":")>=0:
                ip = "[%s]:%s" % (host,port)
            else:
                ip = host+":"+str(port)
            line = re.sub('(\d+)\.(\d+)\.(\d+)\.(\d+)', ip, line)
            print str(re.sub('\n','',line))


class gpfdist2(unittest.TestCase):
    def setUp(self):
        run("rm -rf gpfdist2/*.log")
        run("rm -rf gpfdist2/data/*.log")
        killall('gpfdist')

    def tearDown(self):
        run("rm -rf gpfdist2/*.log")
        run("rm -rf gpfdist2/data/*.log")
        killall('gpfdist')

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


    def doTest(self, num, start_gpfdist = True, options = False, comment = False, modify_sql = True, filename='query', port=None):
        if num == 10000:

           run_gpfdist(options, port=port2)
           return 
        prefix = '%s%d' % (filename,num)
        
        run("mkdir test")
        run("cp -f %s* test/" % (prefix))
        filename = mkpath("test", filename)
        if port == None:
           port=port1
        if modify_sql:
              modify_sql_file(filename+str(num),port)
        if not comment:
            comment = ''
        if not options:
            options = ' -d ' + UPD 
        if not start_gpfdist:
            file = mkpath('%s%d.sql' % (filename,num))
            runfile(file,comment)
        else:
            run_gpfdist(options, port=port)
            file = mkpath('%s%d.sql' % (filename,num))
            runfile(file,comment)
            killall('gpfdist')
        self.check_result(file)

    def testQuery00(self): 
        "gpfdist2: setup"
        file = mkpath('setup.sql')
        runfile(file)
    def testQuery01(self):
        "gpfdist2: 1 using a .gz file  "
        self.doTest(1)

    def testQuery02(self): 
        "gpfdist2: 2 using a .bz2 file  "
        self.doTest(2)
        
    def testQuery03(self): 
        "gpfdist2: 3 using invalid files (.z, .zip)  "
        self.doTest(3)
    
    def testQuery04(self): 
        "gpfdist2: 4 column data type does not match  "
        self.doTest(4)     
    
    def testQuery05(self): 
        "gpfdist2: 5 data has extra or missing attributes  "
        self.doTest(5)
    
    def testQuery06(self): 
        "gpfdist2: 6 using non-default port  "
        new_port=9000
        self.doTest(6,True,port=new_port)

    def testQuery07(self): 
        "gpfdist2: 7 external table attributes (encoding, escape, etc)  "
        self.doTest(7)
    
    def testQuery08(self): 
        "gpfdist2: 8 external table attributes (escape off)  "
        self.doTest(8)
    
    def testQuery09(self): 
        "gpfdist2: 9 external table attributes csv (force not null)  "
        self.doTest(9)    

    def testQuery10(self): 
        "gpfdist2: 10  "
        self.doTest(10)
        
    def testQuery11(self): 
        "gpfdist2: 11  "
        self.doTest(11)
    
    def testQuery12(self): 
        "gpfdist2: 12  "
        self.doTest(12)
    
    def testQuery13(self): 
        "gpfdist2: 13  "
        self.doTest(13)    
    
    def testQuery14(self): 
        "gpfdist2: 14  "
        self.doTest(14)
    
    def testQuery15(self): 
        "gpfdist2: 15  "
        self.doTest(15)
    
    def testQuery16(self): 
        "gpfdist2: 16  "
        self.doTest(16)
    
    def testQuery17(self): 
        "gpfdist2: 17  "
        self.doTest(17)
    
    def testQuery18(self): 
        "gpfdist2: 18  "
        self.doTest(18)

    def testQuery19(self): 
        "gpfdist2: 19  "
        self.doTest(19)

    def testQuery20(self): 
        "gpfdist2: 20  "
        run("gpssh -h " + hostname + " -e \'chmod 000 %s/data/bad_data/lineitem.tbl.no_read \'" % MYD)
        self.doTest(20)
        run("gpssh -h " + hostname + " -e \'chmod 744 %s/data/bad_data/lineitem.tbl.no_read\'" % MYD)


    def testQuery21(self): 
        "gpfdist2: 21  "
        self.doTest(21)

    def testQuery22(self): 
        "gpfdist2: 22  "
        self.doTest(22,True,False,'-a')

    def testQuery23(self): 
        "gpfdist2: 23  "
        self.doTest(23)
    
    def testQuery24(self): 
        "gpfdist2: 24  "
        self.doTest(24)
    
    def testQuery25(self): 
        "gpfdist2: 25  "
        self.doTest(25)
    
    def testQuery26(self): 
        "gpfdist2: 26  "
        self.doTest(26)
    
    def testQuery28(self): 
        "gpfdist2: 28 gpfdist with no options "
        self.doTest(28)
        
    def testQuery29(self): 
        "gpfdist2: 29 gpfdist with -d option "
        options = "-d %s/gpfdist2/data" % UPD
        self.doTest(29,True,options)

    def testQuery31(self): 
        "gpfdist2: 31 gpfdist invalid port "
        self.doTest(31,False)

    def testQuery32(self): 
        "gpfdist2: 32 gpfdist invalid dir "
        self.doTest(32,False)
              
    def testQuery34(self): 
        "gpfdist2: 34 gpfdist deprecated options "
        self.doTest(34)

    def testQuery38(self): 
        "gpfdist2: 38 gpfdist with -l and -v option "
        options = "-l %s/log.log -v -d %s" % (MYD , UPD)
        self.doTest(38,True,options)
        p = subprocess.Popen(['ssh', hostname, 'ls '+UPD+'/gpfdist2/log.log'], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        if re.search('No such file',p.stdout.read()):
            raise Exception('Log file did not get written to')

    def testQuery39(self): 
        "gpfdist2: 39 gpfdist invalid logfile "
        self.doTest(39)
    
    def testQuery40(self): 
        "gpfdist2: 40 gpfdist with -l and -V option "
        options = "-l %s/log.log -v -d %s" % (MYD , UPD)
        self.doTest(40,True,options)
        p = subprocess.Popen(['ssh', hostname, 'ls '+UPD+'/gpfdist2/log.log'], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        if re.search('No such file',p.stdout.read()):
            raise Exception('Log file did not get written to')

    def testQuery41(self): 
        "gpfdist2: 41 gpfdist with all options "
        options = "-d %s/gpfdist2/data -l log.log -V" % UPD
        self.doTest(41,True,options)
        p = subprocess.Popen(['ssh', hostname, 'ls '+UPD+'/gpfdist2/data/log.log'], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        if re.search('No such file',p.stdout.read()):
            raise Exception('Log file did not get written to')       

    def testQuery44(self): 
        "gpfdist2: 44 invalid data  "
        self.doTest(44)        

    def testQuery45(self): 
        "gpfdist2: 45 without header row and header is defined in format clause  "
        self.doTest(45)
        
    def testQuery46(self): 
        "gpfdist2: 46 with header row but header is not defined in format clause  "
        self.doTest(46)
        
    def testQuery47(self): 
        "gpfdist2: 47 without header row and header is not defined in format clause  "
        self.doTest(47)
        
    def testQuery48(self): 
        "gpfdist2: 48 rows with missing or extra attributes  "
        self.doTest(48)
        
    def testQuery49(self): 
        "gpfdist2: 49 2 gpfdist processes "
        # start gpfdist on port 8081. doTest will start gpfdist on port 8080
        new_port=port2
        self.doTest(10000,True,port=new_port, options = ' -d ' + UPD)
        self.doTest(49,port=port1,options = ' -d ' + UPD )

    def testQuery50(self): 
        "gpfdist2: 50 multiple files  "
        self.doTest(50)
        
    def testQuery51(self): 
        "gpfdist2: 51 2 gpfdist processes and 2 files"
        # start gpfdist on port 8081. doTest will start gpfdist on port 8080
        new_port=port2
        self.doTest(10000,True,port=new_port, options = ' -d ' + UPD)
        self.doTest(51,port=port1,options = ' -d ' + UPD)
        #mygpfdist.killGpfdist()

    def testQuery52(self): 
        "gpfdist2: 52 table creation commands  "
        self.doTest(52)

    def testQuery53(self): 
        "gpfdist2: 53 external table attributes text (force not null)  "
        self.doTest(53)        

    def testQuery54(self): 
        "gpfdist2: 54 Regression MPP-3370 - inherit external table"
        self.doTest(54)

    def testQuery55(self): 
        "gpfdist2: 55 using timeout option"
        options = "-t 10 -d " + UPD
        self.doTest(55,True,options)  

    def testQuery56(self): 
        "gpfdist2: 56 using timeout option - negative"
        self.doTest(56,False)

    def testQuery57(self): 
        "gpfdist2: 57 using timeout option - negative"
        self.doTest(57,False)
        
    def testQuery58(self): 
        "gpfdist2: 58 using m option - negative"
        self.doTest(58,False)
        
    def testQuery59(self): 
        "gpfdist2: 59 using m option - negative"
        self.doTest(59,False)
        
    def testQuery60(self): 
        "gpfdist2: 60 using m option - negative"
        options = "-m 32768 -d "+ UPD
        self.doTest(60,True,options)  

    def testQuery61(self): 
        "gpfdist2: 61 using m option"
        options = "-m 327680 -d " + UPD
        self.doTest(61,True,options)
 
    def testQuery62(self): 
        "gpfdist2: 62 line too long with defaults"
        self.doTest(62)         

    def testQuery63(self):
        "gpfdist2: 63 MPP-6491- select from external table sometimes give 'invalid string enlargement' error"
        self.doTest(63)

    def testQuery65(self):
        "gpfdist2: 65 Indexed AO (Append-Only) tables"
        self.doTest(65, start_gpfdist = True, comment = "-a")

    def test_MPP5993(self): 
        "gpfdist2: MPP-5993: GPFDIST has a limit on the line length"
        options = "-m 350000 -d " + UPD
        self.doTest(5993,True,options ,filename='mpp')
     
        
###########################################################################
#  Try to run if user launched this script directly
#     [YOU SHOULD NOT CHANGE THIS]
if __name__ == '__main__':
    suite = unittest.TestLoader().loadTestsFromTestCase(gpfdist2)
    runner = unittest.TextTestRunner(verbosity=2)
    ret = not runner.run(suite).wasSuccessful()
    sys.exit(ret)
