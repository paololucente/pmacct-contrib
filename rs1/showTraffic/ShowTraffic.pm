# Perl Module
#
# $Id: ShowTraffic.pm,v 3.3 2004/09/06 17:02:12 root Exp root $


BEGIN { $Exporter::Verbose=0 };

package ShowTraffic;

use Exporter ();
use strict;
use integer;
use English;
use FileHandle;
use File::Basename;
use File::DosGlob 'glob';
use Time::Local;	# contains conversion for struct time -> serial
use Shell;	# fuer cp
use DBI;
use Date::Calc qw(:all);
use Sys::Hostname;


@ShowTraffic::ISA = qw(Exporter);

@ShowTraffic::EXPORT = qw( 
grepInFile
getCfgValue
readField
mapAgentID2Interface
readTrafficRows
parseMonthList
parsePortList
parseInterfaceList
getInOutBytes
getIFName
getIPAddress
showTrafficOfInterface
getInterfaceData

);


#
# Variablen die von aussen zugaenglich sind
#
$ShowTraffic::DEBUG 		= 0;
$ShowTraffic::Version 		= '$Revision: 3.3 $';


# --- Begin of ModuleBody ---

sub grepInFile( $$ ) {
    my ( $fileName, $searchString ) = @_;
    # ---
    my( @fileContents, @result );

    print "DEBUG: Configile in Funktion grepInFile=$fileName\n" if $ShowTraffic::DEBUG;
    if ( -f $fileName ) {
        open FH, "<$fileName";
        @fileContents =  <FH>;
        close FH;
        @result = grep /$searchString/, @fileContents;
    } else {
        print "ERROR: File :$fileName: not found\n";
    }
    return ( @result );
}

sub getCfgValue( $$$ ) {
    my ( $cfgFile, $key, $default ) = @_;
    # ---
    my ( @keyLine, $value, $num, $confFile );

    $confFile = $cfgFile;
    if ( ! -f $confFile ) {
        # ok not found in ./ try /etc
        if ( -f "/etc/$cfgFile" ) {
            $confFile = "/etc/$cfgFile";
        }
    }

    if ( -f $confFile ) {
        #
        @keyLine = `egrep ^$key $confFile`;
        $num = @keyLine;
        if ( $num ) {
            print "keyLine from $cfgFile:  -@keyLine-\n" if $ShowTraffic::DEBUG;
            ( $key, $value ) = split( /=\s*/, $keyLine[0] );
            chomp( $value );    # remove \n 
            print "Extracted value :$value:\n" if $ShowTraffic::DEBUG;
            return ( $value );
        } else {
            print "ERROR Key $key not found in $confFile\n" if $ShowTraffic::DEBUG;
        }
    } else {
        print "ERROR ConfigFile $confFile not found\n" if $ShowTraffic::DEBUG;
    }
    print "Returning default = $default\n" if $ShowTraffic::DEBUG;

    return ( $default );
}


sub readField( $$ ) {
    my ( $dbh, $statement ) = @_;
    # ---
    my ( $sth, @arr, $rc, $field  );

    $sth = $dbh->prepare( $statement ) or die "Can't prepare statement: $DBI::errstr";
    $rc = $sth->execute or die "Can't execute statement: $DBI::errstr";
    print "Query will return $sth->{NUM_OF_FIELDS} fields.\n" if $ShowTraffic::DEBUG;

    print "Field names: @{ $sth->{NAME} }\n" if $ShowTraffic::DEBUG;
    while (($field) = $sth->fetchrow_array) {
        print "    found @{ $sth->{NAME} } = $field\n" if $ShowTraffic::DEBUG;
	push @arr, $field;
    }
    # auslesen beenden
    $sth->finish();
    # check for problems which may have terminated the fetch early
    die $sth->errstr if $sth->err;

    return( @arr );
}

# read data from conffiles
sub getID2IFDict( $ ) {
    my ( $path2conf ) = @_;
    # ---
    my ( %dict, @confFiles, $size, $cfgFile, @contents, $interfaceDefinitionLine, $agentIdDefinitionLine, $dummy, $interfaceName, $pmacctd_id );
    
    if ( ! -d $path2conf ) {
        print "ERROR: Configfile directory not found\n";
        return ();
    }
    # get al list of all conf files in $path2conf
    @confFiles = `ls $path2conf/*.conf`;
    $size = @confFiles;
    if ( $size ) {
        print "DEBUG: $size Conffile found in $path2conf\n" if $ShowTraffic::DEBUG;
        foreach $cfgFile ( @confFiles ) {
            open FD, "<$cfgFile";
            @contents = <FD>;
            close FD;
            ( $interfaceDefinitionLine ) = grep /^interface/, @contents;
            chomp( $interfaceDefinitionLine );
            ( $agentIdDefinitionLine ) = grep /^pmacctd_id/, @contents;
            chomp( $agentIdDefinitionLine );
            print "DEBUG: found interfaceDefinitionLine=:$interfaceDefinitionLine:\n" if $ShowTraffic::DEBUG;
            print "DEBUG: found agentIdDefinitionLine=:$agentIdDefinitionLine:\n" if $ShowTraffic::DEBUG;
            # get the values
            ( $dummy, $interfaceName ) = split( /:\s+/, $interfaceDefinitionLine );
            $interfaceName =~ s/\s*//g;
            print "DEBUG: interfaceName is now :$interfaceName:\n" if $ShowTraffic::DEBUG;
            # remove all whithespaves because it is used as key for the dict
            ( $dummy, $pmacctd_id ) = split( /:\s+/, $agentIdDefinitionLine );
            $pmacctd_id =~ s/\s*//g;
            print "DEBUG: pmacctd_id is now :$pmacctd_id:\n" if $ShowTraffic::DEBUG;
            # now store it to the return hash
            $dict{ $pmacctd_id } = $interfaceName;
        }
    }
    return ( %dict );
}


sub mapAgentID2Interface( $$ ) {
    my ( $path2confFiles, $arrayRef ) = @_;
    # ---
    my ( %dict, $agentId, $interfaceName, $found, %mappedDict );
    # gets a list of acctIds with assiciated interfacename
    %dict = getID2IFDict( $path2confFiles );
    # now map the configured list against the ids found in database
    foreach $agentId ( @$arrayRef ) {
        print "DEBUG: mapping key=$agentId from database to cfg-File\n" if $ShowTraffic::DEBUG;
        $found = $dict{ $agentId };
        if ( defined( $found )) {
            $interfaceName = $dict{ $agentId };
            $mappedDict{ "$interfaceName" } = "$agentId";
        }
    }
    return ( %mappedDict ); 
}

sub readTrafficRows( $$ ) {
    my ( $dbh, $statement ) = @_;
    #
    my ( $sth, %dict, $rc, $day, $month, $bytes );

    $sth = $dbh->prepare( $statement ) or die "Can't prepare statement: $DBI::errstr";
    $rc = $sth->execute or die "Can't execute statement: $DBI::errstr";
    print "Query will return $sth->{NUM_OF_FIELDS} fields.\n" if $ShowTraffic::DEBUG;
   
    print "Field names: @{ $sth->{NAME} }\n" if $ShowTraffic::DEBUG;
    while (($day, $month, $bytes) = $sth->fetchrow_array) {
        $dict{ "$day.$month" } = $bytes;
        print "  SQL-Result selected Data:: $day  $month $bytes\n" if $ShowTraffic::DEBUG;
    }
    # end read
    $sth->finish();
    # check for problems which may have terminated the fetch early
    die $sth->errstr if $sth->err;

    return ( %dict );
}
 
sub parseMonthList( $ ) {
    my ( $monthListArg ) = @_;	# string with 1,2,3,4,...12
    # ---
    my( @rc, @arr, $mon );

    if ( $monthListArg =~ /all/i ) {
        $monthListArg = qq{1,2,3,4,5,6,7,8,9,10,11,12};
    }
    @arr = split( /,/, $monthListArg );
    # validate
    foreach $mon ( @arr ) {
        if ( $mon <1 or $mon >12 ) {
            print "ERROR: Month $mon is invalid - ignoring it\n";
        } else {
            push @rc, $mon;
        }
    }
    return( @rc );
}

sub parsePortList( $$ ) {
    my ( $portListArg, $defaultList ) = @_;	# string with 80,8080,443,22,21,20,514,25
    # ---
    my( %dict, @rc, $port, $i, $size, @arrayUniq );

    if ( $portListArg =~ /all/i ) {
        $portListArg = $defaultList;
    }
    print "DEBUG: portListArg=:$portListArg:\n" if $ShowTraffic::DEBUG;
    @rc = split( /,/, $portListArg );
    # TODO: validate agains previous collected ports in database
    $size = @rc;
    $i = 1;
    print "DEBUG: found $size number of ports\n" if $ShowTraffic::DEBUG;
    foreach $port ( @rc ) {
        print "port found = $port position=$i\n" if $ShowTraffic::DEBUG;
        # filter for duplicates
        $dict{ "$port" } = $i++;
    }
    # restore original sorting list
    foreach $port ( @rc ) {
        if ( $dict{ $port } ) {
            $dict{ $port } = 0;
            push @arrayUniq, $port;
        }
    }
    return( @arrayUniq );
}

sub parseInterfaceList( $@ ) {
    my ( $interfaceListArg, @allowedNames ) = @_; # string with eth1,tun1,eth7
    # ---
    my ( @arr, @list, $intf, @rc,$size );

    if ( $interfaceListArg =~ /all/i ) {
        $interfaceListArg = join( ',', @allowedNames );
    }
    # parse supplied string " eth1,tun1,eth7"
    @list = split( /,/, $interfaceListArg );
    # vaildate
    foreach $intf ( @list ) {
        @rc = grep /$intf/, @allowedNames;
	$size = @rc;
	if ( $size ) {
	    # ok
	    print "DEBUG: interface $intf validated\n" if $ShowTraffic::DEBUG;
            push @arr, $intf;
	} else {
	    print "ERROR: Interface $intf is invalid ignoring it\n";
	}
    }
    print "DEBUG: Interfaces in List are:\n" if $ShowTraffic::DEBUG;
    foreach ( @arr ) {
        print "DEBUG: found interfaceName=:$_:\n" if $ShowTraffic::DEBUG;
    }
    return ( @arr );
}

sub getInOutBytes( $ ) {
    my( $rawLine ) =@_;
    # ---
    my( @inOutLines, @rc, $line );

    if ( ! defined( $rawLine) || ! length( $rawLine )) {
        return ( "0.0", "0.0" );
    }
    #print "DEBUG: analyseLine:$rawLine;\n" if $ShowTraffic::DEBUG;

    # in rawLine steht:
    #           RX bytes:0 (0.0 b)  TX bytes:0 (0.0 b)
    @rc = ();
    @inOutLines = split( /\s+TX/, $rawLine );
    foreach $line ( @inOutLines ) {
        #print "DEBUG: working on $line\n" if $ShowTraffic::DEBUG;
        $line =~ s/.*\((.*)\)/$1/;
	push @rc, $line;
	#print "DEBUG: line after subst=:$line:\n" if $ShowTraffic::DEBUG;
    }
    return ( @rc );
}    


sub getIFName( $ ) {
    my( $rawLine ) = @_;
    # ---
    my( $ifName );

    # in rawLine steht
    # vmnet2    Link encap:Ethernet  HWaddr 00:50:56:C0:00:02
    
    ( $ifName ) = split( /\s+/, $rawLine );
    print "DEBUG: name=:$ifName:\n" if $ShowTraffic::DEBUG;

    return( $ifName );
}


sub getIPAddress( $ ) {
    my ( $rawLine ) = @_;
    # ---
    my ( $rawAddressLine, $ip, $dummy );

    # in rawLine steht: "          inet addr:192.168.2.1  Bcast:192.168.2.255  Mask:255.255.255.0"
    ( $dummy, $rawAddressLine ) = split( /:/, $rawLine );
    #print "DEBUG: rawAddressLine=:$rawAddressLine:\n";
    ( $ip ) = split( /\s+/, $rawAddressLine );
    #print "DEBUG: ip=:$ip:\n";

    return ( $ip );
}    


sub showTrafficOfInterface( @ ) {
    my ( @ifDefinition ) = @_;
    # ---
    my ( $ifName, $ifAddress, $inBytes, $outBytes, $line );

    # the array contains
    # vmnet2    Link encap:Ethernet  HWaddr 00:50:56:C0:00:02
    #           inet addr:192.168.2.1  Bcast:192.168.2.255  Mask:255.255.255.0
    #           UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1
    #           RX packets:0 errors:0 dropped:0 overruns:0 frame:0
    #           TX packets:0 errors:0 dropped:0 overruns:0 carrier:0
    #           collisions:0 txqueuelen:1000
    #           RX bytes:0 (0.0 b)  TX bytes:0 (0.0 b)
    ( $ifName ) = getIFName(  $ifDefinition[ 0 ] );
    ( $ifAddress ) = getIPAddress( $ifDefinition[ 1 ] );
    ( $line ) = grep /bytes/, @ifDefinition;
    ( $inBytes, $outBytes ) = getInOutBytes( $line );
    print "DEBUG: found Interface: $ifName\n" if $ShowTraffic::DEBUG;
    print "DEBUG: found Address  : $ifAddress\n" if $ShowTraffic::DEBUG;
    print "DEBUG: found InBytes  : $inBytes\n" if $ShowTraffic::DEBUG;
    print "DEBUG: found OutBytes : $outBytes\n" if $ShowTraffic::DEBUG;
    printf ( "%-10s %-16s %-10s %-10s\n", $ifName, $ifAddress, $inBytes, $outBytes ) if $ShowTraffic::DEBUG;
    return ( $ifName, $ifAddress, $inBytes, $outBytes );
}


sub getInterfaceData( $ ) {
    my ( $interfaceName ) = @_;
    # ---
    my ( @out, @rc, @interfaceDefinitionsArray );

    print "DEBUG: getting interface data for $interfaceName\n" if $ShowTraffic::DEBUG;
    # printf ( "%-10s %-16s %-10s %-10s\n", "ifName", "ifAddress", "inBytes", "outBytes" );
    @out = `ifconfig $interfaceName`;

    foreach  ( @out ) {
        if ( /^eth|vmnet|tun|lo/ ) {
            #print "DEBUG: anfang einer interface definition gefunden\n" if $ShowTraffic::DEBUG;
	    #print "DEBUG: $_\n" if $ShowTraffic::DEBUG;
	    # vmnet2    Link encap:Ethernet  HWaddr 00:50:56:C0:00:02
	    # oder
	    #eth0:FWB1 Link encap:Ethernet  HWaddr 00:A0:80:00:13:EA
	    # oder
	    # eth0:4    Link encap:Ethernet  HWaddr 00:A0:80:00:13:EA
	    #
	    chomp;
   	    @interfaceDefinitionsArray = ( $_ ); 

        }
        if ( /^\s+/ ) {
	    #print "DEBUG: $_\n" if $ShowTraffic::DEBUG;
            #  inet addr:192.168.2.1  Bcast:192.168.2.255  Mask:255.255.255.0
            #  UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1
            #  RX packets:0 errors:0 dropped:0 overruns:0 frame:0
            #  TX packets:0 errors:0 dropped:0 overruns:0 carrier:0
            #  collisions:0 txqueuelen:1000
            #  RX bytes:0 (0.0 b)  TX bytes:0 (0.0 b)
            # or
            # if it is an alias definition line
            #
            #      inet addr:172.17.68.54  Bcast:172.17.68.255  Mask:255.255.255.0
            #  UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1
            #  Interrupt:14 Base address:0xec00
	    chomp;
   	    push @interfaceDefinitionsArray, $_; 

        }
        if ( /^$/ ) {
	    #print "DEBUG: End of an  Interfacedefinition found\n" if $ShowTraffic::DEBUG;
	    #print "DEBUG: $_\n" if $ShowTraffic::DEBUG;
	    #foreach $line ( @interfaceDefinitionsArray ) {
	    #    print "DEBUG: Line=$line\n" if $ShowTraffic::DEBUG;
	    #}
    	    @rc = showTrafficOfInterface( @interfaceDefinitionsArray );
	    print "DEBUG: ---- NEXT ----\n" if $ShowTraffic::DEBUG;
            return ( @rc );
        }

    }
}

1;
# vim:set noai et sts=4 sw=4 tw=0:
# eof
