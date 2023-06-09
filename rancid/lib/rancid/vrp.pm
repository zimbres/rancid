package vrp;
##
## rancid 3.12
## Copyright (c) 1997-2019 by Henry Kilmer and John Heasley
## All rights reserved.
##
## This code is derived from software contributed to and maintained by
## Henry Kilmer, John Heasley, Andrew Partan,
## Pete Whiting, Austin Schutz, and Andrew Fort.
##
## Redistribution and use in source and binary forms, with or without
## modification, are permitted provided that the following conditions
## are met:
## 1. Redistributions of source code must retain the above copyright
##    notice, this list of conditions and the following disclaimer.
## 2. Redistributions in binary form must reproduce the above copyright
##    notice, this list of conditions and the following disclaimer in the
##    documentation and/or other materials provided with the distribution.
## 3. Neither the name of RANCID nor the names of its
##    contributors may be used to endorse or promote products derived from
##    this software without specific prior written permission.
##
## THIS SOFTWARE IS PROVIDED BY Henry Kilmer, John Heasley AND CONTRIBUTORS
## ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
## TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
## PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COMPANY OR CONTRIBUTORS
## BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
## CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
## SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
## INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
## CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
## ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
## POSSIBILITY OF SUCH DAMAGE.
##
## It is the request of the authors, but not a condition of license, that
## parties packaging or redistributing RANCID NOT distribute altered versions
## of the etc/rancid.types.base file nor alter how this file is processed nor
## when in relation to etc/rancid.types.conf.  The goal of this is to help
## suppress our support costs.  If it becomes a problem, this could become a
## condition of license.
# 
#  The expect login scripts were based on Erik Sherk's gwtn, by permission.
# 
#  The original looking glass software was written by Ed Kern, provided by
#  permission and modified beyond recognition.
#
#  RANCID - Really Awesome New Cisco confIg Differ
#
#  vrp.pm - Hauwei VRP rancid procedures

use 5.010;
use strict 'vars';
use warnings;
no warnings 'uninitialized';
require(Exporter);
our @ISA = qw(Exporter);

use rancid 3.12;

our $C0;				# output formatting control
our $E0;
our $H0;
our $I0;

@ISA = qw(Exporter rancid main);
#XXX @Exporter::EXPORT = qw($VERSION @commandtable %commands @commands);

# load-time initialization
sub import {
    0;
}

# post-open(collection file) initialization
sub init {
    $C0 = 0;				# output formatting control
    $E0 = 0;
    $H0 = 0;
    $I0 = 0;

    # add content lines and separators
    ProcessHistory("","","","#RANCID-CONTENT-TYPE: $devtype\n#\n");
    ProcessHistory("COMMENTS","keysort","B0","#\n");
    ProcessHistory("COMMENTS","keysort","C0","#\n");
    ProcessHistory("COMMENTS","keysort","D0","#\n");
    ProcessHistory("COMMENTS","keysort","E0","#\n");
    ProcessHistory("COMMENTS","keysort","E2","#\n");
    ProcessHistory("COMMENTS","keysort","F0","#\n");
    ProcessHistory("COMMENTS","keysort","G0","#\n");

    0;
}

# main loop of input of device output
sub inloop {
    my($INPUT, $OUTPUT) = @_;
    my($cmd, $rval);

TOP: while(<$INPUT>) {
	tr/\015//d;
	if (/>\s?quit$/) {
	    $clean_run = 1;
	    last;
	}
	# due to errors from commands in xilogin XXX
	next if (/^error: (file can.t be found.|unrecognized command)/i);
	if (/^Error:/) {
	    print STDOUT ("$host clogin error: $_");
	    print STDERR ("$host clogin error: $_") if ($debug);
	    $clean_run = 0;
	    last;
	}
	while (/[>#]\s*($cmds_regexp)\s*$/) {
	    $cmd = $1;
	    if (!defined($prompt)) {
		$prompt = ($_ =~ /^([^>]+>)/)[0];
		$prompt =~ s/([][}{)(+\\])/\\$1/g;
		print STDERR ("PROMPT MATCH: $prompt\n") if ($debug);
	    }
	    print STDERR ("HIT COMMAND:$_") if ($debug);
	    if (! defined($commands{$cmd})) {
		print STDERR "$host: found unexpected command - \"$cmd\"\n";
		$clean_run = 0;
		last TOP;
	    }
	    if (! defined(&{$commands{$cmd}})) {
		printf(STDERR "$host: undefined function - \"%s\"\n",
		       $commands{$cmd});
		$clean_run = 0;
		last TOP;
	    }
	    $rval = &{$commands{$cmd}}($INPUT, $OUTPUT, $cmd);
	    delete($commands{$cmd});
	    if ($rval == -1) {
		$clean_run = 0;
		last TOP;
	    }
	}
    }
}

# This routine parses "display version"
sub DispVersion {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In DispVersion: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	next if (/^(\s*|\s*$cmd\s*)$/);
	last if (/^$prompt/);
	next if (/^\s+\^$/);
	return(1) if (/((invalid|unrecognized) (input|command) detected|type help or )/i);
	return(-1) if (/failed to pass the authorization/i);

	next if (/^\s*VRP(\s\S+)?\s*software\s*,\s*version/i);
	next if (/^\s*huawei versatile routing platform software/i);
	next if (/^\s*copyright .*/i);

	s/\s+uptime\s.*//;
	/^huawei\s(.*)/i &&
	    ProcessHistory("COMMENTS","keysort","A1", "#Chassis type: $1\n") && next;
	if (/^DDR\s*Memory\s*Size\s*:\s(.*)/i) {
	    $_ = $1;
	    s/  */ /g;
	    ProcessHistory("COMMENTS","keysort","B1", "#Memory: $_\n") && next;
	}
	/^software\s*version\s*:\s(.*)/i &&
	    ProcessHistory("COMMENTS","keysort","D1", "#Image: $1\n");

	ProcessHistory("COMMENTS","keysort","E3", "#$_");
    }
    return(0);
}

# This routine parses "display startup"
sub DispStartup {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In DispStartup: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	next if (/^(\s*|\s*$cmd\s*)$/);
	last if (/^$prompt/);
	next if (/^\s+\^$/);
	return(1) if (/((invalid|unrecognized) (input|command) detected|type help or )/i);
	return(-1) if (/failed to pass the authorization/i);

	ProcessHistory("COMMENTS","keysort","D2", "#$_") && next;
    }
    return(0);
}

# This routine parses "display device"
sub DispDevice {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In DispDevice: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	next if (/^(\s*|\s*$cmd\s*)$/);
	last if (/^$prompt/);
	next if (/^\s+\^$/);
	return(1) if (/((invalid|unrecognized) (input|command) detected|type help or )/i);
	return(-1) if (/failed to pass the authorization/i);

	/device status:/i && next;

	ProcessHistory("COMMENTS","keysort","F1", "#$_") && next;
    }
    return(0);
}

# This routine parses "display device manufacture-info"
sub DispDeviceMfg {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In DispDevice: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	next if (/^(\s*|\s*$cmd\s*)$/);
	last if (/^$prompt/);
	next if (/^\s+\^$/);
	return(1) if (/((invalid|unrecognized) (input|command) detected|type help or )/i);
	return(-1) if (/failed to pass the authorization/i);

	ProcessHistory("COMMENTS","keysort","E1", "#$_") && next;
    }
    return(0);
}


# This routine parses "display transceiver verbose"
sub DispTransciever {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In DispTransciever: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	next if (/^(\s*|\s*$cmd\s*)$/);
	last if (/^$prompt/);
	next if (/^\s+\^$/);
	return(1) if (/((invalid|unrecognized) (input|command) detected|type help or )/i);
	return(-1) if (/failed to pass the authorization/i);

	/^$/i && next;
	/valid only on \S+ interface/i && next;
	/^(common|manufacture) information/i && next;
	/^----*/i && next;
	/^diagnostic information/i && last;

	ProcessHistory("COMMENTS","keysort","G1", "#$_") && next;
    }
    return(0);
}

# This routine parses "dir /all /all-filesystems"
sub DirSlotN {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In DirSlotN: $_" if ($debug);

    ProcessHistory("FLASH","","", "#\n");
    while (<$INPUT>) {
	tr/\015//d;
	next if (/^(\s*|\s*$cmd\s*)$/);
	last if (/^$prompt/);
	next if (/^\s+\^$/);
	return(1) if (/((invalid|unrecognized) (input|command) detected|type help or )/i);
	return(-1) if (/failed to pass the authorization/i);

	return(1) if (/(wrong device|no such device|error sending request)/i);
	return(1) if (/\%Error: No such file or directory/);
	return(1) if (/No space information available/);
	return(-1) if (/\%Error calling/);
	return(-1) if (/\%error opening \S+:\S+ \(device or resource busy\)/i);
	return(1) if (/(Open device \S+ failed|Error opening \S+:)/);

	# filter frequently changing files/dirs
	# change from:
	#     8  drw-              -  Mar 24 2018 05:46:04   logfile
	# to:
	#        drw-                                        logfile
	if (/(logfile|vrpcfg.zip)\s*$/) {
	    if (/(\s*\d+)(\s+\S+\s+)([\d,]+|-)(\s+)(\w+ \d+\s+\d+ \d+:\d+:\d+ )/) {
		my($fn, $a, $sz, $c, $dt, $rem) = ($1, $2, $3, $4, $5, $');
		my($fnl, $szl, $dtl) = (length($fn), length($sz), length($dt));
		my($fmt) = "%-". $fnl ."s%s%-". $szl ."s%s%-". $dtl ."s%s";
		$_ = sprintf($fmt, "", $a, "", $c, "", $rem);
	    }
	} else {
	    # drop the file number
	    if (/(\s*\d+)(\s+\S+\s+([\d,]+|-)\s+\w+ \d+\s+\d+ \d+:\d+:\d+ .*)/) {
		my($fn, $rem) = ($1, $2);
		my($fnl) = length($fn);
		my($fmt) = "%-". $fnl ."s%s\n";
		$_ = sprintf($fmt, "", $rem);
	    }
	}

	# summarize the total/free line
	if (/^\s*([\d,]+ \S+)\s+total\s+\(([\d,]+ \S+) free\)/i) {
	    my($sz, $mp) = ($1, $2);
	    $_ = diskszsummary($sz, $mp, undef) . "\n";
	}

	ProcessHistory("FLASH","","","#Flash: $_");
    }
    ProcessHistory("","","","#\n");
    return(0);
}

# This routine parses "display debug"
sub DispDebug {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In DispDebug: $_" if ($debug);
    my($lines) = 0;

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^$/);
	return(1) if (/((invalid|unrecognized) (input|command) detected|type help or )/i);
	return(-1) if (/failed to pass the authorization/i);

	ProcessHistory("COMMENTS","keysort","J1","#DEBUG: $_");
	$lines++;
    }
    if ($lines) {
	ProcessHistory("COMMENTS","keysort","J0","#\n");
    }
    return(0);
}

# This routine processes a "display current-configuration"
sub WriteTerm {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In WriteTerm: $_" if ($debug);
    my($linecnt) = 0;

    while (<$INPUT>) {
TOP:
	tr/\015//d;
	last if (/^$prompt/);
	return(1) if (!$linecnt && /^\s+\^\s*$/);
	next if (/^\s*$cmd\s*$/);
	next if (/^\s+\^\s*$/);
	return(1) if (/((invalid|unrecognized) (input|command) detected|type help or )/i);
	return(-1) if (/failed to pass the authorization/i);

	return(1) if (/\%Error: No such file or directory/);
	return(1) if (/(Open device \S+ failed|Error opening \S+:)/);
	return(0) if ($found_end);		# Only do this routine once
	# skip emtpy lines at the beginning
	if (!$linecnt && /^\s*$/) {
	    next;
	}

	$linecnt++;
	# skip the crap
	/^!\s*software version/i && next;

	# Dog gone Cool matches to process the rest of the config
	if (/^ local-user (\S+)(\s.*)? cipher (\S+)/) {
	    if ($filter_pwds >= 1) {
		ProcessHistory("USER","keysort","$1",
			       "#local-user $1$2 cipher <removed>\n");
	    } else {
		ProcessHistory("USER","keysort","$1","$_");
	    }
	    next;
	}
	if (/^ local-user (\S+)(\s.*)? irreversible-cipher (\S+)/) {
	    if ($filter_pwds >= 2) {
		ProcessHistory("USER","keysort","$1",
			       "#local-user $1$2 irreversible-cipher <removed>\n");
	    } else {
		ProcessHistory("USER","keysort","$1","$_");
	    }
	    next;
	}
	/^ local-user (\S+)(\s.*)? / &&
	    ProcessHistory("USER","keysort","$1", "$_") && next;

	# bgp neighbor passwords
	if (/^(\s+peer \S* password simple)/ && $filter_pwds >= 1) {
	    ProcessHistory("","","","# $1 <removed>\n");
	    next;
	}
	if (/^(\s+peer \S* password cipher)/ && $filter_pwds >= 2) {
	    ProcessHistory("","","","# $1 <removed>\n");
	    next;
	}
# XXX how is bgp policy configured on VRP?
#	# sort route-maps
#	if (/^route-map (\S+)/) {
#	    my($key) = $1;
#	    my($routemap) = $_;
#	    while (<$INPUT>) {
#		tr/\015//d;
#		last if (/^$prompt/ || ! /^(route-map |[ !])/);
#		if (/^route-map (\S+)/) {
#		    ProcessHistory("ROUTEMAP","keysort","$key","$routemap");
#		    $key = $1;
#		    $routemap = $_;
#		} else  {
#		    $routemap .= $_;
#		}
#	    }
#	    ProcessHistory("ROUTEMAP","keysort","$key","$routemap");
#	}
# XXX how are access-lists configured on VRP?
#	# order access-lists
#	/^access-list\s+(\d\d?)\s+(\S+)\s+(\S+)/ &&
#	    ProcessHistory("ACL $1 $2","$aclsort","$3","$_") && next;
#	# order extended access-lists
#	if ($aclfilterseq) {
#	/^access-list\s+(\d\d\d)\s+(\S+)\s+(\S+)\s+host\s+(\S+)/ &&
#	    ProcessHistory("EACL $1 $2","$aclsort","$4","$_") && next;
#	/^access-list\s+(\d\d\d)\s+(\S+)\s+(\S+)\s+(\d\S+)/ &&
#	    ProcessHistory("EACL $1 $2","$aclsort","$4","$_") && next;
#	/^access-list\s+(\d\d\d)\s+(\S+)\s+(\S+)\s+any/ &&
#	    ProcessHistory("EACL $1 $2","$aclsort","0.0.0.0","$_") && next;
#	}
#	if ($aclfilterseq) {
#	    /^ip(v6)? prefix-list\s+(\S+)\s+seq\s+(\d+)\s+(permit|deny)\s+(\S+)(.*)/
#		&& ProcessHistory("PACL $2 $4","$aclsort","$5",
#				  "ip$1 prefix-list $2 $4 $5$6\n")
#		&& next;
#	}
#	# sort ipv{4,6} access-lists
#	if ($aclfilterseq && /^ipv(4|6) access-list (\S+)\s*$/) {
#	    my($nlri, $key) = ($1, $2);
#	    my($seq, $cmd);
#	    ProcessHistory("ACL $nlri $key","","","$_");
#	    while (<$INPUT>) {
#		tr/\015//d;
#		last if (/^$prompt/ || /^\S/);
#		# ipv4 access-list name
#		#  remark NTP
#   		#  deny ipv4 host 224.0.1.1 any
#		#  deny ipv4 239.0.0.0 0.255.255.255 any
#		#  permit udp any eq 123 any
#		#  permit ipv4 nnn.nnn.nnn.nnn/nn any
#		#  permit nnn.nnn.nnn.nnn/nn
#		# ipv6 access-list name
#		#  permit ipv6 host 2001:nnnn::nnnn any
#		#  permit ipv6 2001:nnn::/nnn any
#		#  permit 2001:nnnn::/64 any
#		#  permit udp any eq 123 any
#		#
#		# line might begin with " sequence nnn permit ..."
#		s/^\s+(sequence (\d+)) / /;
#		my($seq) = $1;
#		my($cmd, $resid) = ($_ =~ /^\s+(\w+) (.+)/);
#		if ($cmd =~ /(permit|deny)/) {
#		    my($ip);
#		    my(@w) = ($resid =~ /(\S+) (\S+) (\S+\s)?(.+)/);
#		    for (my($i) = 0; $i < $#w; $i++) {
#			if ($w[$i] eq "any") {
#			    if ($nlri eq "ipv4") {
#				$ip = "255.255.255.255/32";
#			    } else {
#				$ip = "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff/128";
#			    }
#			    last;
#			} elsif ($w[$i] =~ /^[:0-9]/ ||
#				 $2[$i] =~ /^[a-fA-F]{1,4}:/) {
#			    $ip = $w[$i];
#			    $ip =~ s/\s+$//;		# trim trailing WS
#			    last;
#			}
#		    }
#		    ProcessHistory("ACL $nlri $key $cmd", "$aclsort", "$ip",
#				   " $cmd $resid\n");
#		} else {
#		    ProcessHistory("ACL $nlri $key $cmd", "", "",
#				   " $cmd $resid\n");
#		}
#	    }
#	}
# XXX how are static ARPs configured on VRP?
#	# order arp lists
#	/^arp\s+(\d+\.\d+\.\d+\.\d+)\s+/ &&
#	    ProcessHistory("ARP","$aclsort","$1","$_") && next;
# XXX how is logging configured on VRP?
#	# order logging statements
#	/^logging (\d+\.\d+\.\d+\.\d+)/ &&
#	    ProcessHistory("LOGGING","ipsort","$1","$_") && next;
# XXX how is snmp configured on VRP?
#	# order/prune snmp-server host statements
#	# we only prune lines of the form
#	# snmp-server host a.b.c.d <community>
#	if (/^snmp-server host (\d+\.\d+\.\d+\.\d+) /) {
#	    if ($filter_commstr) {
#		my($ip) = $1;
#		my($line) = "snmp-server host $ip";
#		my(@tokens) = split(' ', $');
#		my($token);
#		while ($token = shift(@tokens)) {
#		    if ($token eq 'version') {
#			$line .= " " . join(' ', ($token, shift(@tokens)));
#			if ($token eq '3') {
#			    $line .= " " . join(' ', ($token, shift(@tokens)));
#			}
#		    } elsif ($token eq 'vrf') {
#			$line .= " " . join(' ', ($token, shift(@tokens)));
#		    } elsif ($token =~ /^(informs?|traps?|(no)?auth)$/) {
#			$line .= " " . $token;
#		    } else {
#			$line = "#$line " . join(' ', ("<removed>",
#						 join(' ',@tokens)));
#			last;
#		    }
#		}
#		ProcessHistory("SNMPSERVERHOST","ipsort","$ip","$line\n");
#	    } else {
#		ProcessHistory("SNMPSERVERHOST","ipsort","$1","$_");
#	    }
#	    next;
#	}
# XXX how are tacacs/radius snmp configured on VRP?
#	# prune tacacs/radius server keys
#	if (/^((tacacs|radius)-server\s(\w*[-\s(\s\S+])*\s?key) (\d )?\S+/
#	    && $filter_pwds >= 1) {
#	    ProcessHistory("","","","#$1 <removed>$'"); next;
#	}
# XXX how are static clns hosts configured on VRP?
#	# order clns host statements
#	/^clns host \S+ (\S+)/ &&
#	    ProcessHistory("CLNS","keysort","$1","$_") && next;
# XXX how is ntp configured on VRP?
#	# delete ntp auth password - this md5 is a reversable too
#	if (/^(ntp authentication-key \d+ md5) / && $filter_pwds >= 1) {
#	    ProcessHistory("","","","#$1 <removed>\n"); next;
#	}
#	# order ntp peers/servers
#	if (/^ntp (server|peer) (\d+)\.(\d+)\.(\d+)\.(\d+)/) {
#	    my($sortkey) = sprintf("$1 %03d%03d%03d%03d",$2,$3,$4,$5);
#	    ProcessHistory("NTP","keysort",$sortkey,"$_");
#	    next;
#	}
# XXX can static hosts be configured?
#	# order ip host statements
#	/^ip host (\S+) / &&
#	    ProcessHistory("IPHOST","keysort","$1","$_") && next;

	# catch anything that wasnt matched above.
	ProcessHistory("","","","$_");
	# end of config.  the ": " game is for the PIX
	if (/^return$/) {
	    $found_end = 1;
	    return(0);
	}
    }

    return(0);
}

1;
