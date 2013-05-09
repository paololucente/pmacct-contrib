#!/usr/bin/python

##############################################################################
# Copyright (C) 2009, Karl O. Pinc <kop@meme.com>
# http://www.meme.com/
# 
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation; either version 3 of the License, or (at your
# option) any later version.
# 
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License
# for more details.
# 
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
##############################################################################
#
# Syntax:  See usage() below.
#
# Remarks:
#  This is alpha code.  Works for me.
#
#  Read the usage() function!
#
#  Customize the build_rrd_cmd() function for your data.
#
#  Minimizes load on pmacctd server and avoids timing issues
#  by running pmacct only once per rrd data load.
#
# Bugs:
# - Needs lots-o-cleanup.  Too many hardcoded values.
# - Forking twice is insane.
# - Should probably use python-rrd module.
# - The log format is not quite right.
# - Bad statistics ensue if the subprocess does not complete within
#     POLL_SECS seconds.
# - Ignores (invalid) traffic from the adv-net (private rfc1918)
#   address to the internet.
#
# Todo:
# - Cleanup commented out code!

# Constants
RUN_SECS = 3600
POLL_SECS = 1    # Poll every N seconds
PMACCT = "/home/kop/projects/pmacct/pmacct-0.11.5/src/pmacct"
#PMACCT = "/home/kop/pmacct/pmacct-0.11.5/src/pmacct"
PMACCT_SOCK = "/tmp/pmacct.totals"
PMACCT_CMD = [PMACCT, "-s", "-e", "-p", PMACCT_SOCK]
RRDTOOL = '/usr/bin/rrdtool'

"""
usage: pmacct2rrd
       Collect stats from pmacct and feed them to rrdtool.
       Cron is not very accurate.    This program should be started
       by cron at 5 minutes to the hour.    It will collect stats
       every second for an hour.

"""

import time
import logging
import logging.handlers
import os
import subprocess
import signal

def format_epoch(t):
    """Output standard logging time format.
       Input:    t    Time since epoch in seconds
       Output: String representing time, including milliseconds
       Side Effects: none

    """

    return (time.strftime("%b %d %H:%M:%S"
                          , time.localtime(t)) + ","
                            + str(t % 1)[2:])

def build_rrd_cmd(now, data):
#  Input:
#    now  Timestamp, when the data was collected.
#    data  Output of pmacct command.
#
# For use with a pmacctd config file that looks like:
#   interface: sis0
#   daemonize: true
#   syslog: daemon
#   aggregate[t]: src_net,dst_net
#   networks_file[t]: /etc/pmacct/net/networks
#   imt_path[t]: /tmp/pmacct.net_t
#
# And a networks file that contains something like a
# list of the IP numbers that are natted (with
# a /32 netmask) or the networks routed via different
# gateways.

    """Transform pmacct output into an rrd command
    Hour of 10 second intervals
    8 hours of 1 minute intervals
    1 week of 30 minute intervals
    Uses: rrdtool create /var/lib/pmacct/net.rrd --step 1 \
          DS:t1_1_in_pkts:ABSOLUTE:2:0:U \
          DS:t1_1_out_pkts:ABSOLUTE:2:0:U \
          DS:t1_1_in_bytes:ABSOLUTE:2:0:19300 \
          DS:t1_1_out_bytes:ABSOLUTE:2:0:19300 \
          DS:t1_2_in_pkts:ABSOLUTE:2:0:U \
          DS:t1_2_out_pkts:ABSOLUTE:2:0:U \
          DS:t1_2_in_bytes:ABSOLUTE:2:0:19300 \
          DS:t1_2_out_bytes:ABSOLUTE:2:0:19300 \
          RRA:MAX:.9:10:360 \
          RRA:AVERAGE:.9:10:360 \
          RRA:MAX:.1:60:480 \
          RRA:AVERAGE:.1:60:480 \
          RRA:MAX:.1:1800:336 \
          RRA:AVERAGE:.1:1800:336 
    """

    RRD = '/var/lib/pmacct/net.rrd'
    TEMPLATE = 't1_1_in_pkts:t1_1_out_pkts' \
               ':t1_1_in_bytes:t1_1_out_bytes' \
               ':t1_2_in_pkts:t1_2_out_pkts' \
               ':t1_2_in_bytes:t1_2_out_bytes'

    # Index into pmacct data
    SRC_IP = 0
    DST_IP = 1
    PACKETS = 2
    BYTES = 3

    # 2 networks routed over 2 paths by a gateway on 192.168.192.0/24.
    DFLT = '0.0.0.0'
    NET1 = '9.9.9.0'   # A /27 network
    NET2 = '9.9.9.32'  # A /27 network
    LOCAL = '192.168.192.0'

    UVAL = 'U'

    def bad_data(cols):
        """Received bad src,dst pair"""
        logger.error(  'src: ' + cols[SRC_IP]
                     + ' dst: ' + cols[DST_IP]
                     + ' pkts: ' + cols[PACKETS]
                     + ' bytes: ' + cols[BYTES]
                     + ' : unknown src,dst pair')

    lines = data.splitlines()

    # Convert all the data lines into rrd format

    # Analyze data
    t1_1_in_pkts = UVAL
    t1_1_out_pkts = UVAL
    t1_2_in_pkts = UVAL
    t1_2_out_pkts = UVAL
    t1_1_in_bytes = UVAL
    t1_1_out_bytes = UVAL
    t1_2_in_bytes = UVAL
    t1_2_out_bytes = UVAL
    for line in lines[1:-2]:  # Ignore pmacct's annoyng header & footer
        cols = line.split()
        if cols[SRC_IP] == NET1:
            if cols[DST_IP] == DFLT:
                t1_1_out_pkts = cols[PACKETS]
                t1_1_out_bytes = cols[BYTES]
            else:
                bad_data(cols)
        elif cols[SRC_IP] == NET2:
            if cols[DST_IP] == DFLT:
                t1_2_out_pkts = cols[PACKETS]
                t1_2_out_bytes = cols[BYTES]
            else:
                bad_data(cols)
        elif cols[DST_IP] == NET1:
            if cols[SRC_IP] == DFLT:
                t1_1_in_pkts = cols[PACKETS]
                t1_1_in_bytes = cols[BYTES]
            else:
                bad_data(cols)
        elif cols[DST_IP] == NET2:
            if cols[SRC_IP] == DFLT:
                t1_2_in_pkts = cols[PACKETS]
                t1_2_in_bytes = cols[BYTES]
            else:
                bad_data(cols) 
        #elif (cols[SRC_IP] == LOCAL and cols[DST_IP] == DFLT)
        #     or (cols[DST_IP] == LOCAL and cols[SRC_IP] == DFLT):
        elif (cols[SRC_IP] == LOCAL
              or cols[DST_IP] == LOCAL):
            # Ignore traffic to/from the local private (dmz-ish)
            # network.
            pass
        else:
            bad_data(cols)



# SRC_IP           DST_IP           PACKETS     BYTES
# 
# t1_1_in_pkts
# t1_1_out_pkts
# t1_2_in_pkts
# t1_2_out_pkts
# 
# t1_1_in_bytes
# t1_1_out_bytes
# t1_2_out_bytes
# t1_2_in_bytes

    rrd_data = ':'.join([  str(now)
                         , t1_1_in_pkts, t1_1_out_pkts
                         , t1_1_in_bytes, t1_1_out_bytes
                         , t1_2_in_pkts, t1_2_out_pkts
                         , t1_2_in_bytes, t1_2_out_bytes])

    # Save the data
    #print '-------------'
    #print data
    #print TEMPLATE
    #print rrd_data
    #os._exit(os.EX_OK)

    return [ RRDTOOL, 'update'
            , RRD
            , '-t', TEMPLATE
            , rrd_data]


#def collect_stats(now):
#    """(Asynchronously) collect stats from pmacct for the
#    time "now"."""
#
#    try:
#        #if os.fork() != 0:
#        child = os.fork()
#        if child != 0:
#            # In parent
#            def kill_zombie(sig, frame):
#                os.waitpid(child,0)
#            # Turn off "I'm done" signals from the child so it can go to
#            # its' final rest without becoming a zombie.
#            signal.signal(signal.SIGCHLD, kill_zombie)
#        else:
#            # In child
#            logger.debug("collecting stats for " + format_epoch(now))
#            try:
#                pmacct = subprocess.Popen(args = PMACCT_CMD
#                                          , stdout=subprocess.PIPE
#                                          , stderr=subprocess.PIPE
#                                          , cwd="/tmp/")
#                result = pmacct.communicate()
#                if pmacct.returncode != 0 or result[1] != "":
#                    # There was an error.
#                    logger.error("error running pmacct: "
#                                  + str(pmacct.returncode)
#                                  + ": "
#                                  + result[1])
#                    # Keep going even though there was an error.
#
#                data = result[0]
#                print data
#
#            except OSError:
#                logger.error("unable to run pmacct")
#                raise
#
#            os._exit(os.EX_OK)
#
#    except OSError:
#        logger.exception("unable to fork "
#                         + format_epoch(now)
#                         + " collection process")
#        raise # re-raise the exception

def collect_stats(now):
    """(Asynchronously) collect stats from pmacct for the
    time "now"."""

    def save_stats(data):
        """Save pmacct output in rrdtool"""

        try:
            rrdtool = subprocess.Popen(  args = build_rrd_cmd(now, data)
                                       , stderr=subprocess.PIPE
                                       , close_fds=True
                                       , cwd='/tmp/')
            result = rrdtool.communicate()
            if rrdtool.returncode != 0 or result[1] != '':
                #print str(rrdtool.returncode) + ': ' + result[1]
                logger.warning("error running rrdtool update: "
                               + str(rrdtool.returncode)
                               + ": "
                               + result[1])
        except OSError:
            logger.exception("unable to execute rrdtool update for"
                             + format_epoch(now))
            raise # re-raise the exception

    try:
        child = os.fork()
        if child != 0:
            # In parent
            os.waitpid(child, 0) # reap the child, avoid zombies
        else:
            # In child
            # fork again to keep the parent from waiting on wait().
            # (This is stupid, but ignoring or defining an alternate
            # signal handler for SIGCHLD seems to break the subprocess
            # module.  Debian etch.  Python 2.4.)
            if os.fork() == 0:
                # In child
                logger.debug("collecting stats for " + format_epoch(now))

                try:
                    pmacct = subprocess.Popen(args = PMACCT_CMD
                                              , stdout=subprocess.PIPE
                                              , stderr=subprocess.PIPE
                                              , cwd="/tmp/")
                    result = pmacct.communicate()
                    if pmacct.returncode != 0 or result[1] != "":
                        # There was an error.
                        logger.error("error running pmacct: "
                                      + str(pmacct.returncode)
                                      + ": "
                                      + result[1])
                        # Keep going even though there was an error.

                    save_stats(result[0])

                except OSError:
                    logger.error("unable to run pmacct")
                    raise

		logger.debug("finished collecting stats for "
			     + format_epoch(now))
                os._exit(os.EX_OK)
            os._exit(os.EX_OK)

    except OSError:
        logger.exception("unable to fork "
                         + format_epoch(now)
                         + " collection process")
        raise # re-raise the exception

#
# Main
#
        
# Set up logging
logger = logging.getLogger("pmacct_collect")
logger.setLevel(logging.DEBUG)
# Log to syslog
sl = logging.handlers.SysLogHandler(
        "/dev/log"
        , logging.handlers.SysLogHandler.LOG_DAEMON)
sl.setLevel(logging.WARNING)
#sl.setLevel(logging.DEBUG)
sl.setFormatter(
    logging.Formatter("%(asctime)s %(name)s[%(process)d]" 
                      " - %(levelname)s: %(message)s"))
logger.addHandler(sl)

logger.info("process started")

try:
    # Wait for the next hour to start.
    #print "not sleeping for the hour"
    secs_to_hour = RUN_SECS - time.time() % RUN_SECS
    logger.debug("sleeping " + str(secs_to_hour) + " seconds until the hour")
    time.sleep(secs_to_hour)
    
    # When is the next hour?
    now = time.time()
    stop_time = now - now % RUN_SECS + RUN_SECS
    logger.debug("running until " + format_epoch(stop_time))
    
    # Keep running until the hour runs out.
    while True:
        now = time.time()
        if now >= stop_time:
            break
    
        collect_stats(now)
    
        # Wait for the next second
        time.sleep(POLL_SECS - time.time() % POLL_SECS)
    
    logger.info("process finished normally")

except:
    logger.warn("process terminated unexpectedly")
    raise
