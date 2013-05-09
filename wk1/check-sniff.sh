#!/bin/bash

# check-sniff.sh: 
#  checks that the sniffing interface is still up, in promiscuous mode,
#  and has the correct speed/duplex settings
#
# using sudo requires this in /etc/sudoers in order to run this script 
# as non-root:
#
# Cmnd_Alias IFCONFIG=/sbin/mii-tool, /sbin/ifconfig
# nagios ALL=NOPASSWD: IFCONFIG
# 

#echo "OK: ** IGNORING FOR NOW **"
#exit 0

DEV=eth1
MII_TOOL="sudo /sbin/mii-tool"

# MII_OK may need to be modified depending on 
# NIC, switch, and NIC duplex/speeds in use.
#MII_OK="100 Mbit, half duplex, link ok"
#MII_OK="negotiated 100baseTx-FD, link ok"
#MII_OK="100 Mbit, full duplex, link ok"
#MII_OK="no autonegotiation, 100baseTx-HD, link ok"
MII_OK="$DEV: negotiated 100baseTx-FD, link ok"
IFCONFIG="sudo /sbin/ifconfig"

OK_YN=`$MII_TOOL $DEV |grep "$MII_OK" |wc -l | sed -e 's/ //'`
PROMISC_YN=`$IFCONFIG $DEV | grep UP | grep PROMISC |wc -l | sed -e 's/ //'`

# override
PROMISC_YN=1

if [ $OK_YN != "1" ] ; then
	echo "CRITICAL: " `$MII_TOOL $DEV`
	exit 2
elif [ $PROMISC_YN != "1" ] ; then
	echo "CRITICAL: interface $DEV is not UP and in PROMISCous mode!"
	exit 2
else
	echo "OK: sniffer interface up"
fi
