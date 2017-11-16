#!/usr/bin/env python
'''
gpmgmt2: Management Utilities 2
'''


############################################################################
# Set up some globals, and import gptest 
#    [YOU DO NOT NEED TO CHANGE THESE]
#
import sys, unittest, os, time, md5
import subprocess
MYD = os.path.abspath(os.path.dirname(__file__))
mkpath = lambda *x: os.path.join(MYD, *x)
UPD = os.path.abspath(mkpath('..'))
if UPD not in sys.path:
    sys.path.append(UPD)
#import gptest
import urllib
_dataPath = mkpath('_data')

def run(cmd):
    """
    Run a shell command. Return (True, [result]) if OK, or (False, []) otherwise.
    @params cmd: The command to run at the shell.
            oFile: an optional output file.
            mode: What to do if the output file already exists: 'a' = append;
            'w' = write.  Defaults to append (so that the function is
            backwards compatible).  Yes, this is passed to the open()
            function, so you can theoretically pass any value that is
            valid for the second parameter of open().
    """
    p = subprocess.Popen(cmd,shell=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    out = p.communicate()[0]
    ret = []
    ret.append(out)
    rc = False if p.wait() else True
    return (rc,ret)

def killall(procname):
    #Anu: removed the path for pkill from /bin/pkill to pkill - assuming that pkill is always in the path.
    cmd = "bash -c 'pkill %s || killall %s' > /dev/null 2>&1" % (procname, procname)
    return run(cmd)
###########################################################################
#  A Test class must inherit from gptest.GPTestCase
#    [CREATE A CLASS FOR YOUR TESTS]
#
class gpfdist1(unittest.TestCase):

    lineitem_md5 = None

    def _readMd5(self, fp):
        m = md5.new()
        cnt = 0
        while True:
            d = fp.read(1024*16)
            if not d: break
            m.update(d)
            cnt = cnt + len(d)

        m = m.hexdigest()
        #print 'cnt =', cnt, ' m =', m
        return m


    def setUp(self):
        (ok, out) = killall('gpfdist')
        cmd = 'gpfdist -v -d %s >> %s 2>&1 &' % (_dataPath, mkpath('gpfdist.out'))
        (ok, out) = run(cmd)
        if not ok: 
            raise Exception('Unable to start gpfdist')
        if not os.path.exists('%s/lineitem.tbl' % _dataPath):
            (ok, out) = run('cd %s && gzip -d -c lineitem.tbl.gz > lineitem.tbl' % _dataPath)
            if not ok:
                raise Exception('Unable to gunzip lineitem.tbl.gz')
        if not gpfdist1.lineitem_md5:
            f = open('%s/lineitem.tbl' % _dataPath)
            gpfdist1.lineitem_md5 = self._readMd5(f)
            f.close()
        time.sleep(1)

    def tearDown(self):
        killall('gpfdist')
        #run('rm -rf %s/split' % _dataPath)

    def test_1simple(self):
        f = os.popen('curl -H "X-GP-PROTO:0" -s -S http://localhost:8080/lineitem.tbl')
        m = self._readMd5(f)
        self.failUnless(m == gpfdist1.lineitem_md5)
        self.failUnless(not f.close())

    def test_2simple_gz(self):
        f = os.popen('curl -H "X-GP-PROTO:0" -s -S http://localhost:8080/lineitem.tbl.gz')
        m = self._readMd5(f)
        self.failUnless(m == gpfdist1.lineitem_md5)
        self.failUnless(not f.close())

    def test_3glob(self):
        (ok, out) = run('cd %s && rm -rf split0 && mkdir split0 && cd split0 && split -l 500 ../lineitem.tbl' % _dataPath)
        self.failUnless(ok)
        
        # take everything under the split0 dir
        f = os.popen('curl -H "X-GP-PROTO:0" -s -S http://localhost:8080/split0')
        m = self._readMd5(f)
        self.failUnless(not f.close())
        self.failUnless(m == gpfdist1.lineitem_md5)

        # take only files x* under the split0 dir
        f = os.popen('curl -H "X-GP-PROTO:0" -s -S http://localhost:8080/split0/x\*')
        m = self._readMd5(f)
        self.failUnless(not f.close())
        self.failUnless(m == gpfdist1.lineitem_md5)

        # gzip 2nd file in split0 dir, and try to take mixture of x?? and x*.gz
        (ok, out) = run('cd %s/split0 && gzip xab' % _dataPath)
        self.failUnless(ok)
        f = os.popen('curl -H "X-GP-PROTO:0" -s -S http://localhost:8080/split0')
        m = self._readMd5(f)
        self.failUnless(not f.close())
        self.failUnless(m == gpfdist1.lineitem_md5)

        # add empty files in between x* files
        (ok, out) = run('cd %s/split0 && touch xaaa xaba xaca xzza' % _dataPath)
        self.failUnless(ok)
        f = os.popen('curl -H "X-GP-PROTO:0" -s -S http://localhost:8080/split0')
        m = self._readMd5(f)
        self.failUnless(not f.close())
        self.failUnless(m == gpfdist1.lineitem_md5)

        #if True:
        #    return

        # split[0]
        f = os.popen('curl -H "X-GP-PROTO:0" -s -S http://localhost:8080/%s' % urllib.quote('split[0]'))
        m = self._readMd5(f)
        self.failUnless(not f.close())
        self.failUnless(m == gpfdist1.lineitem_md5)

        # glob directories
        (ok, out) = run('cd %s && rm -rf split1 split2 && mkdir split1 split2' % _dataPath)
        self.failUnless(ok)
        # ... move last 5 files to ../split2/
        (ok, out) = run("bash -c 'cd %s/split0 && mv $(ls -1 x* | tail -5) ../split2/'" % _dataPath)
        self.failUnless(ok)

        f = os.popen('curl -H "X-GP-PROTO:0" -s -S http://localhost:8080/split?')
        m = self._readMd5(f)
        self.failUnless(not f.close())
        self.failUnless(m == gpfdist1.lineitem_md5)
        
        
    def test_4error(self):
        # no such file
        (ok, out) = run('curl -H "X-GP-PROTO:0" -s -S -w %{http_code} http://localhost:8080/nosuchfile')
        self.failUnless(int(out[0]) == 404)

        # https://daniel.haxx.se/blog/2013/07/30/dotdot-removal-in-libcurl/
        # forbid ..
        #(ok, out) = run('curl -H "X-GP-PROTO:0" -s -S -w %{http_code} http://localhost:8080/a/../b')
        #self.failUnless(int(out[0]) == 400)

        # no permission to read
        (ok, out) = run('cd %s && touch cannotread && chmod -r cannotread' % _dataPath)
        self.failUnless(ok)
        (ok, out) = run('curl -H "X-GP-PROTO:0" -s -S -w %{http_code} http://localhost:8080/cannotread')
        self.failUnless(int(out[0]) == 404)

    def test_5emptyfile(self):
        (ok, out) = run('cd %s && touch empty' % _dataPath)
        self.failUnless(ok)
        (ok, out) = run('curl -H "X-GP-PROTO:0" -s -S -w %{http_code} http://localhost:8080/empty')
        #print 'OUT OUT OUT =', out[0]
        self.failUnless(len(out) == 1 and len(out[0]) == 3)
        self.failUnless(int(out[0]) == 200)

    
###########################################################################
#  Try to run if user launched this script directly
#     [YOU SHOULD NOT CHANGE THIS]
if __name__ == '__main__':
	suite = unittest.TestLoader().loadTestsFromTestCase(gpfdist1)
	runner = unittest.TextTestRunner(verbosity=2)
	ret = not runner.run(suite).wasSuccessful()
	sys.exit(ret)
