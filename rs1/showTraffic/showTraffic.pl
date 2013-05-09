#!/usr/bin/perl -w
#
# Dataextraction for pmacct with mysqlbackend
# pmacct is written and maintained by Paolo Lucente <paolo.lucente@ic.cnr.it>
# Docu can be found at the end of the file as pod
# read it with perldoc ./showTraffic
# If you are in a huryy here a very short quick start
# install pmacct and mysql
# setup version2 database with pmacctd_id for each interface
# start pmacct
# produce some traffic :-))
# edit showTraffic conf to fit your preferred settings as defaults
# call ./showTraffic for a list with all requestet interfaces for 
# traffic summery and alternativly 
# call ./showTraffic --byport to get a list of traffic sorted by port
# for a full list of options see showTraffic --help
#
# (w) 17.Aug 2004 Robert Sailer
# (c) Robert Sailer <robert.sailer@gmx.net>
#
# Licanse: GPL
# 
#
# $Id: showTraffic,v 3.2 2004/09/06 17:02:12 root Exp root $
#
# Thanks to Paolo Lucente for testing
#

use strict;
use English;
use DBI;
use Getopt::Long;
use Date::Calc qw(:all);
use Sys::Hostname;
use lib( '.' );
use ShowTraffic;

my $DEBUG = 0;
my $CONFIGFILE = "showTraffic.conf";
my $CONFIGFILEPATH = "/etc/pmacct";
my $DEFAULTPORTLIST = "22,25,53,80,110,443,995";

# commandLineParameters and their defaults
my $MonthListArg = "1"; # set by main to actual month;
my $InterfaceListArg = "eth1";
my $PortListArg = $DEFAULTPORTLIST;
my $Help = 0;
my $ByPort = 0;
my $Sum = 0;
my $Year = '2004';  # set by main to actual year
my $WithLegend = 1;  # show legend for each shown interface at the end of the report

sub usage() {
    print "usage: $PROGRAM_NAME\n";
    print "Paramerters:\n";
    print "  -i | --interface=ppp0,eth1,eth2,eth3,tun1|ALL\n";
    print "  -m | --month=1,2,3,4,5,6,7,8,9,10,11,12|ALL\n";
    print "  -y | --year=2004\n";
    print "  -b | --byport\n"; 
    print "  -p | --port=22,80,443,50130,6000\n"; 
    print "  -s | --sum\n"; 
    print "  -l | --withLegend\n"; 
    print "  -? | -h | --help\n"; 
    print " Sample: ./showTraffic --interface=eth1,ppp0 -s -l\n";
    print "You can set defaults in ./showTraffic.conf or /etc/showTraffic.conf\n";
    exit 0;
}

#
# main starts here
#


my ( $key, $day, %interfaces, @agentIds, $statement, $databaseHandle, $i );
my ( $interfaceName, $bytes, $dictPtr, @interfaceList, @monthList );
my ( $month, %sumDict, $daysInMonth, $size, @dstPorts, $rc );
my ( $port, %ports, $dbUser, $dbPass, $dbName, @portListAsArray );

if ( defined(  $ENV{ 'DEBUG' }) &&  $ENV{ 'DEBUG' } eq '1' ) {
    $DEBUG = $ENV{ 'DEBUG' };
    print "DEBUG: Debugging enabled via Environmetvariable DEBUG\n" if $DEBUG;
    $ShowTraffic::DEBUG = $DEBUG;
}

# set default parameters
($Year, $MonthListArg, $day)  = Today();

# parse configfile
$dbUser = getCfgValue( $CONFIGFILE, "DB_USER", "pmacct" );
$dbPass = getCfgValue( $CONFIGFILE, "DB_PASS", "pmacct" );
$dbName = getCfgValue( $CONFIGFILE, "DB_NAME", "pmacct" );
$InterfaceListArg = getCfgValue( $CONFIGFILE, "DefaultInterface", "eth0" );
$Sum = getCfgValue( $CONFIGFILE, "WithSummingLine", "1" );
$CONFIGFILEPATH = getCfgValue( $CONFIGFILE, "configFilePath", "/etc/pmacct" );

# parse user supplied options
$rc = GetOptions ('m|month=s' => \$MonthListArg, 'i|interface=s' => \$InterfaceListArg, 'help|?|h' => \$Help, 'b|byport', => \$ByPort, 's|sum' => \$Sum, 'y|year=s' => \$Year, 'p|port=s' => \$PortListArg, "l|withLegend" => \$WithLegend );

usage() if $Help;
usage() if !$rc;

# debug
print "DEBUG: CommandLineOptions:\n" if $DEBUG;
print "monthListArg=:$MonthListArg:\n" if $DEBUG;
print "interfaceList=:$InterfaceListArg:\n" if $DEBUG;
print "byport=$ByPort\n" if $DEBUG;
print "portListArg=:$PortListArg:\n" if $DEBUG;
print "sum=$Sum\n" if $DEBUG;
print "year=$Year\n" if $DEBUG;
print "help=$Help\n" if $DEBUG;

# try to open database
$databaseHandle = DBI->connect( "DBI:mysql:$dbName", $dbUser, $dbPass, { RaiseError => 1, AutoCommit => 0 } ) or die "Can't connect to DBI:mysql:pmacct $DBI::errstr";

# find corresponding interfaces via configfiles
# get a list of all agent_ids in database ( agent_id field )
$statement = qq{ SELECT DISTINCT agent_id FROM acct_v2  };
@agentIds = readField( $databaseHandle, $statement );
foreach $key ( @agentIds ) {
    print "DEBUG: AgentID found = $key\n" if $DEBUG;
}

%interfaces = mapAgentID2Interface( $CONFIGFILEPATH, \@agentIds );
print "DEBUG: check interfaces after mapping\n" if $DEBUG;
foreach $key ( keys %interfaces ) {
    print "DEBUG: InterfaceName=:$key: Value=:$interfaces{ $key }:\n" if $DEBUG;
}

# parse supplied arguments
@monthList = parseMonthList( $MonthListArg );
@interfaceList = parseInterfaceList( $InterfaceListArg, keys( %interfaces ));

# check traffic or portstatistics
if ( $ByPort ) {
    my $interface = $interfaceList[0];
    # read interfacespecific portlist

    # generate statistics by dest port
    print "DEBUG: generate report by ports\n" if $DEBUG;
    # this will work with exactly one interface
    $size = @interfaceList;
    print "DEBUG: Number of Interfaces found = $size\n" if $DEBUG;
    if ( $size eq 1 ) {
        $PortListArg = getCfgValue( $CONFIGFILE, "DefaultPortList.$interface", "22" );
        @portListAsArray = parsePortList( $PortListArg, $DEFAULTPORTLIST );
        print "portListArg=:$PortListArg for interface $interface:\n" if $DEBUG;
        print "DEBUG; Interface=$interfaceList[0]\n" if $DEBUG;
        # build appropriate query
        foreach $port ( @portListAsArray ) {
            my %portsDict = ();
            print "DEBUG: collecting data for port $port\n" if $DEBUG;
            $statement = "SELECT dayofmonth( stamp_inserted), month( stamp_inserted), sum(bytes) FROM acct_v2 where agent_id = $interfaces{ $interfaceList[0] } and year(stamp_inserted) = $Year and ( dst_port = $port or src_port = $port) GROUP BY MONTH( stamp_inserted), DAYOFMONTH( stamp_inserted )";
            print "DEBUG: SQL: $statement\n" if $DEBUG;
            %portsDict = readTrafficRows( $databaseHandle, $statement );
            # in dict steht jetzt ein monat mit einem port traffic pro tag
            $ports{ $port } = \%portsDict; 
        }
    } else {
        print "ERROR: exactly one interface is supported - Abort\n";
        # close the database
        $databaseHandle->disconnect;
        exit 1;
    }
} else {
    # generate statistc by overall traffic
    print "DEBUG: generate report by traffic\n" if $DEBUG;

    foreach $interfaceName ( keys( %interfaces )) {
        print "DEBUG; Interface=$interfaceName( id=$interfaces{ $interfaceName})\n" if $DEBUG;
        my %dict = ();
        # build appropriate query
        $statement = "SELECT dayofmonth( stamp_inserted), month( stamp_inserted), sum(bytes) FROM acct_v2 where agent_id = $interfaces{ $interfaceName } and year(stamp_inserted) = $Year GROUP BY MONTH( stamp_inserted ), DAYOFMONTH( stamp_inserted )";
        print "DEBUG: SQL-Query=:$statement:\n" if $DEBUG;

        %dict = readTrafficRows( $databaseHandle, $statement );
        foreach my $key ( keys( %dict )) {
            print "DEBUG: Data key=$key value=$dict{ $key }\n" if $DEBUG;
        }
        $interfaces{ $interfaceName } = \%dict; 
    }

}
# -----------------------------------------------------------------------------
#
# data collection finished
# close the database
$databaseHandle->disconnect;

my $output2screen = 1;
if ( $output2screen ) {
    # --------
    # Output
    # --------

    # some sanity 
    $size = @interfaceList;
    if ( ! $size ) {
        print "ERROR: no valid interfaces found\n";
        print "valid Interfaces are:\n";
        foreach $interfaceName ( keys( %interfaces )) {
            print "$interfaceName\n";
        } 
        usage();
    }

    my $timeString = localtime();
    my $hostname = hostname();
    my $user = $ENV{ 'USER' };

    # for every Month a new sheet with caption
    foreach $month ( @monthList ) {
        $daysInMonth = Date::Calc::Days_in_Month($Year,$month);
        #
        # tablecaption
        #
        my $monthName = Date::Calc::Month_to_Text($month);
        print "Report for $monthName $Year\n";
        print "created at $timeString at $hostname by $user\n";
        # sortiert nacht verkehr von und zu ports pro interface
        if ( $ByPort ) {
            print "Data for interface: $interfaceList[0]\n";
            print "Day    ";
            foreach my $portNum ( @portListAsArray ) {
                printf ( "    %-4d ", $portNum );
            }
        } else {
            print "Day    ";
            foreach $interfaceName ( @interfaceList ) {
                print "-$interfaceName/KB ";
            }
        }
        print "\n";

        # now do the output
        %sumDict = ();
        for ( $i=1; $i<=$daysInMonth; $i++ ) {
            my $dow = Day_of_Week( $Year, $month, $i );
            # my $dayName = Day_of_Week_to_Text( $dow );
            my $dayName = Day_of_Week_Abbreviation( $dow );
            printf( "%3s %2d ", $dayName, $i );
            if ( $ByPort ) {
                foreach $port ( @portListAsArray ) {
                    $dictPtr = $ports{ $port };
                    $bytes = $$dictPtr{ "$i.$month" };
                    if ( ! defined( $bytes )) {
                        $bytes = 0;
                    } else {
                        $bytes = $bytes / 1024;
                    }
                    $sumDict{ $port } += $bytes;
                    # i is the day in the acual month
                    printf( "%8d ", $bytes );
                }
            } else {
                foreach $interfaceName ( @interfaceList ) {
                    $dictPtr = $interfaces{ $interfaceName };
                    $bytes = $$dictPtr{ "$i.$month" };
                    if ( ! defined( $bytes )) {
                        $bytes = 0;
                    } else {
                        $bytes = $bytes / 1024;
                    }
                    $sumDict{ $interfaceName } += $bytes;
                    # i is the day in the acual month
                    printf( "%8d ", $bytes );
                }
            }
            print "\n";
        }
        if ( $Sum ) {
            print "Sum:   ";
            if ( $ByPort ) {
                foreach $port ( @portListAsArray ) {
                    printf( "%8d ", $sumDict{ $port });
                }
            } else {
                foreach $interfaceName ( @interfaceList ) {
                    printf( "%8d ", $sumDict{ $interfaceName });
                }
            }
            print "\n";
        }
        # does user wish to have a descriptive footer?
        if ( $WithLegend ) {
            print "\nLegend:\n";
            foreach $interfaceName ( @interfaceList ) {
                my @description = getInterfaceData( $interfaceName );
                printf ( "%-10s %-16s %-10s %-10s (since uptime)\n", @description );
            }
            print "\n";
        }
    }
}

# documentation starts here:
=head1 Name

showTraffic


=head1 Project

contributed software for pmacct 


=head1 Modul

showTraffic


=head1 Description

showTraffic can be used to analyse Data written by pmacct to a database
like mysql. 
There are to modes to show data
First ist to show all traffic by interface in and out.
Second is to show traffic at a list of ports for one interface

=head2 switches

=head3 --interface

takes a list of interfacenames like ppp0,eth1,eth2,eth3,tun1,tr0
As a special argument you can use "ALL" which stands for all interfaces
that are accounted in the database.

=head3  --month

takes the ordinal of a month in a year 
1,2,3,4,5,6,7,8,9,10,11,12|ALL
Suppling ALL will report a whole year.

=head3  --year

takes the year with 4digits to report on 

=head3  --byport

With this switch you can change the resulting report If set only one interface can be reported at a time.
It can be used in conjunction with the port list.

=head3   --port

takes a comma seperated list of ports to report 22,80,443,50130,6000

=head3 --sum

Adds a collum summ line to the end of the report

=head3  --withLegend

Use this switch to get a description of each interface shown in the report


=head3  --help

Shows a short usage try it is harmless


=head1 ConfigFile

All data can be supplied as default values in the configfile ./showTraffic.conf
or /etc/showTraffic.conf. The file in pwd is preferred.

Settable values are:

#
# config file for showTraffic
#

# database info
DB_USER = pmacct
DB_PASS = pmacct
DB_NAME = pmacct

# where to find the configfiles of pmacctd
configFilePath = /etc/pmacct

# which interface to report
DefaultInterface = eth1

# list of ports to report (interface specific)
DefaultPortList.eth1 = 22,25,53,80,110,443,995,50130
DefaultPortList.tun1 = 22,443,995

# add a line with colum sums at the end of the table
WithSummingLine = 1

=head1 Samples

./showTraffic --interface=eth1,tun1,tun3 --sum

./showTraffic --interface=tun1 --sum

./showTraffic --interface=tun1 --sum --byport --port=22,443,563


=head1 Platform

Tested on debian 3.1 IntelArch with mysql4 and perl 5.8
But it should work on every unix where perl works

=head1 Author

S<Robert Sailer, E<lt>F<robert.sailer@gmx.net>E<gt>>


=head1 Copyright

(c) Robert Sailer E<lt>F<robert.sailer@gmx.net>E<gt>>

=head1 License

GPL

=cut




# vim:set noai et sts=4 sw=4 tw=0:
#
