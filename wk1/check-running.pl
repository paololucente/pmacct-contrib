#!/usr/bin/perl -w

# check-running.pl
#  Description:	 Nagios plugin script for pmacct
#  Author:       Wim Kerkhoff, wim@nyetwork.org
#  License:      Same as pmacct
#
#  This script can be added as a service check in Nagios to ensure
#  that pmacct is counting traffic properly. The SQL below is written for
#  PostgreSQL but could easily be tweaked to run with MySQL. It will probably
#  have to be tweaked for your counter configuration anyway.
#
#  Call with one of five arguments: promisc, hourly, daily, monthly, all
#
#  Database username/password is defined at the bottom.

use strict;
use DBI;

our $mode = $ARGV[0] || "all";
our $exitcode = 0;

&check_procs;

our $dbh = &db_connect();
&check_promisc($dbh, "1.1.1.1", 2, '5 minutes') if $mode =~ /all|promisc/;
&check_table($dbh, "acct", "date_trunc('hour',now())", "2 hour", 600) if $mode =~ /all|hourly/;
&check_table($dbh, "acct_daily", "now()::date", "1 day", 700) if $mode =~ /all|daily/;
&check_table($dbh, "acct_monthly", "date_trunc('month', now())", "1 month", 1000) if $mode =~ /all|monthly/;
$dbh->disconnect;

exit $exitcode;


############

sub check_promisc() {
	# this checks that pmacct is sniffing the pings that are being sent 
	# from this system to the internet
	my ($dbh, $icmp_addr, $minrows, $interval) = @_;
	my $sql = " 
		set enable_seqscan = false;
	 SELECT 
	 	count(1) as ok
	 from 
	 	acct 
	where 
		--ip_proto =1 AND 
		stamp_inserted::timestamp >= (now() - interval '2 hours')::timestamp AND
		stamp_updated >= (now() - interval '$interval')::timestamp AND
		coalesce(ip_src, ip_dst) = ? 
	";

	my $sth = $dbh->prepare($sql) 
		|| &suicide($!);
	$sth->execute ($icmp_addr)
		|| &suicide($!);
	my ($count, $mb) = $sth->fetchrow;

	if ($count < $minrows) {
		print "CRITICAL: Found $count rows in the last $interval, wanted at least $minrows!\n";
		$exitcode = 2;
	} else {
		print "OK: Found $count rows in the last $interval. > $minrows, good.\n";
	}
}

sub check_procs {
	# check that some database connections are up.
	my $count = `ps axf |grep "postgres: stats" |wc -l`;
	chomp($count);
	$count =~ s/ //;
	$count ||= 0;

	if ($count < 2) {
		print "CRITICAL: postgres doesn't seem to be running??\n";
		$exitcode = 2;
		exit;
	}
}

sub check_table {
	my ($dbh, $table, $s, $interval, $minrows) = @_;

	my $sql = "
		set enable_seqscan = false;
		select count(1), round(sum(bytes)/1024/1024, 2)
		from $table 
		where stamp_inserted::timestamp >= ($s - interval '$interval')::timestamp
	";
	#print $sql;
	my $sth = $dbh->prepare($sql) 
		|| &suicide($!);
	$sth->execute 
		|| &suicide($!);
	my ($count, $mb) = $sth->fetchrow;

	$mb ||= 0;
	$count ||= 0;

	if ($count < $minrows) {
		print "CRITICAL: $count rows ($mb mb) in the last $interval, wanted at least $minrows!\n";
		$exitcode = 2;
	} else {
		print "OK: Found $count rows ($mb mb) rows in the last $interval. > $minrows, good.\n";
	}
}

sub suicide {
	my ($mesg) = $_[0] || $!;
	
	print "CRITICAL: $mesg\n";
		$exitcode = 2;
	$dbh->disconnect if $dbh;
	exit;
}

sub db_connect {
	#my $dsn = "DBI:mysql:database=pmacct;"; #host=localhost;port=$port";
	#my $user = "";
	#my $password = "";

	my $dsn = "DBI:Pg:dbname=pmacct"; #host=localhost;port=$port";
	my $user = "pmacct";
	my $password = "arealsmartpwd";

	return DBI->connect($dsn, $user, $password) 
		|| &suicide($!);
}
