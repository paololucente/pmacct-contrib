<?
// Correct the PATHs to your needs 
// ( usually it's a good idea to have an include folder out of document root)

require "./xtpl.p";
require "dbconfig.inc";
require "./pagedresults.php";

$rowsperpage = 30 ; // Num of rows per page. tune it to avoid timeouts
$resolvenames = 1; // set it to zero to disable name resolving 

// Code 

$db = mysql_connect($host, $user, $pass);
$open_db = mysql_select_db($dbname, $db);

$sql="select ip_src, src_port, ip_dst, dst_port, ip_proto, packets, stamp_inserted, stamp_updated from acct order by stamp_updated desc";

$result= new  MySQLPagedResultSet ($sql, $rowsperpage, $db);

$xtpl= new XTemplate ("templates/traffic.html");
if (!$result) {
	print "erro  sql=$sql\n";
	exit();
}
							
while($myrow = $result->fetchArray()) {
	$proto=$myrow["ip_proto"];
	
	if ($resolvenames==1) {
		$sport=getservbyport($myrow["src_port"], $proto);
		$dport=getservbyport($myrow["dst_port"], $proto);
	} else {
		$sport=$myrow["src_port"];
		$dport=$myrow["dst_port"];
	}
	// Workaround if there is no name specified
	// PHP returns null, better have a number than null
	
	if ($sport=="") $sport=$myrow["src_port"];
	if ($dport=="") $dport=$myrow["dst_port"];
	
	$xtpl->assign("SPORT", $sport);
	$xtpl->assign("DPORT", $dport);

	if ($resolvenames == 1) {
		$xtpl->assign("SIP", gethostbyaddr($myrow["ip_src"]));
		$xtpl->assign("DIP", gethostbyaddr($myrow["ip_dst"]));
	} else {
		$xtpl->assign("SIP", $myrow["ip_src"]);
		$xtpl->assign("DIP", $myrow["ip_dst"]);

	}
	$xtpl->assign("PROTO", $proto);
	$xtpl->assign("PACKETS", $myrow["packets"]);
	$xtpl->assign("START_DATE", $myrow["stamp_inserted"]);
	$xtpl->assign("LAST_PACKET_DATE", $myrow["stamp_updated"]);
	$xtpl->parse("main.item");
}

$xtpl->assign("FOOTER", $result->getPageNav());

$xtpl->parse("main");
$xtpl->out("main");


mysql_close($db);

?>

