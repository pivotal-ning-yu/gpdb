#!/usr/bin/env python
'''
gpfdist_end_of_line
'''

"""
@author: Yael Paz (yael.paz@emc.com)

@description: Use the line_delim='line_ending' parameter to specify the line ending character.

@copyright: Copyright (c) 2012 EMC Corporation All Rights Reserved
This software is protected, without limitation, by copyright law
and international treaties. Use of this software and the intellectual
property contained therein is expressly limited to the terms and
conditions of the License Agreement under which it is provided by
or on behalf of EMC.
"""
############################################################################
# Set up some globals
#    [YOU DO NOT NEED TO CHANGE THESE]

import sys, unittest, os, string, signal, socket, subprocess, time, fileinput, re
MYD = os.environ['MYD'] = os.path.abspath(os.path.dirname(__file__))
UPD = os.environ['UPD'] = os.path.abspath(os.path.join(MYD,'..'))
if UPD not in sys.path:
    sys.path.append(UPD)
from time import sleep
from lib.gpfdist_test import *

def modify_sql_file(filename):
    replace_str(filename,"sql")
    replace_str(filename,"ans")

def replace_str(filename,ext="sql"):
    file = mkpath(filename+"." + ext)
    if os.path.isfile(file):
        for line in fileinput.FileInput(file,inplace=1):
            # gpfdist://[ipv6]:8080
            if line.find("gpfdist")>=0 and host.find(":")>=0:
                ip = "[%s]" % (host)
            else:
                ip = host+":"+str(8080)
            line = re.sub('(\d+)\.(\d+)\.(\d+)\.(\d+)', ip, line)
            print str(re.sub('\n','',line))



class gpfdist_end_of_line(unittest.TestCase):
       
    def setUp(self):
        path='export MYD1='+MYD+'/data/fixedwidth_out.tbl'
        run('rm -f '+MYD+'/data/fixedwidth_out.tbl')
    
    def tearDown(self):
        run('rm -f '+MYD+'/data/fixedwidth_out.tbl')

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

    def doTest(self,num, start_gpfdist = True, options = False, comment = False, modify_sql = True, filename='query'):
        prefix = '%s%d' % (filename,num)
        run("cp -f %s.* test/" % (prefix))
        filename = mkpath("test", filename)
        if modify_sql:
            modify_sql_file(filename+str(num))
        if not comment:
            comment = ''
        if not options:
            options = ''    
        if not start_gpfdist:
            file = mkpath('%s%d.sql' % (filename,num))
            runfile(file,comment)
        else:
            run_gpfdist('-d ' + UPD, 8080)
            file = mkpath('%s%d.sql' % (filename,num))
            runfile(file,comment)
            killall('gpfdist')
        self.check_result(file)

    def testQuery00(self): 
        "end_of_line-setup"
        run("rm -rf test") 
	run("mkdir test")
        file = mkpath('setup.sql')
        runfile(file)

    def testQuery01(self): 
        "end_of_line1-without line_delim"
        self.doTest(1)
        
    def testQuery02(self): 
        "end_of_line2-line_delim=E'n'"
        self.doTest(2)
        
    def testQuery03(self): 
        "end_of_line3-line_delim=E'nr'"
        self.doTest(3)
    
    def testQuery04(self): 
        "end_of_line4-line_delim=(long string)"
        self.doTest(4)
    
    def testQuery05(self): 
        "end_of_line5-line_delim=(space)"
        self.doTest(5) 

    def testQuery06(self): 
        "end_of_line6-line_delim='123'"
        self.doTest(6)
        
    def testQuery07(self): 
        "end_of_line7-line_delim=123"
        self.doTest(7)
       
    def testQuery08(self): 
        "end_of_line8-line_delim='x'"
        self.doTest(8)
        
    def testQuery09(self): 
        "end_of_line9-line_delim=(space) for RET & WET"
        self.doTest(9)
        
    def testQuery10(self): 
        "end_of_line10-line_delim='@'"
        self.doTest(10)
        
    def testQuery11(self): 
        "end_of_line11-line_delim=@"
        self.doTest(11)
   
    def testQuery12(self): 
        "end_of_line12-line_delim='x' for RET & line_delim='EndOfLine' for WET"
        self.doTest(12)
       
    def testQuery13(self): 
        "end_of_line13-line_delim='x'for RET & line_delim=E'n'for WET"
        self.doTest(13)
        
    def testQuery14(self): 
        "end_of_line14-line_delim='x' for RET & line_delim='xxxxxxxxxxxx' for WET"
        self.doTest(14)
    
    def testQuery15(self): 
        "end_of_line15-line_delim='@' for RET & line_delim='x' for WET"
        self.doTest(15)
    
    def testQuery16(self): 
        "end_of_line16-line_delim=E'n' for RET & line_delim='xx' for WET"
        self.doTest(16)
  
    def testQuery17(self): 
        "end_of_line17-line_delim='@' for RET & line_delim=E'n' for WET"
        self.doTest(17)
        
        
###########################################################################
#  Try to run if user launched this script directly
#     [YOU SHOULD NOT CHANGE THIS]
if __name__ == '__main__':
    suite = unittest.TestLoader().loadTestsFromTestCase(gpfdist_end_of_line)
    runner = unittest.TextTestRunner(verbosity=2)
    ret = not runner.run(suite).wasSuccessful()
    sys.exit(ret)

