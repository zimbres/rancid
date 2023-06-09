package fxos;
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
#  fxos.pm - Cisco FXOS rancid procedures

use 5.010;
use strict 'vars';
use warnings;
no warnings 'uninitialized';
require(Exporter);
our @ISA = qw(Exporter);

use rancid 3.12;

our $proc;

our $type;				# device model, from ShowVersion

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
    $proc = "";

    $C0 = 0;				# output formatting control
    $E0 = 0;
    $H0 = 0;
    $I0 = 0;

    # add content lines and separators
    ProcessHistory("","","","!RANCID-CONTENT-TYPE: $devtype\n!\n");
    ProcessHistory("COMMENTS","keysort","B0","!\n");
    ProcessHistory("COMMENTS","keysort","D0","!\n");
    ProcessHistory("COMMENTS","keysort","F0","!\n");
    ProcessHistory("COMMENTS","keysort","G0","!\n");

    0;
}

# main loop of input of device output
sub inloop {
    my($INPUT, $OUTPUT) = @_;
    my($cmd, $rval);

TOP: while(<$INPUT>) {
	tr/\015//d;
	if (/[>#]\s?exit$/) {
	    $clean_run = 1;
	    last;
	}
	if (/^Error:/) {
	    print STDOUT ("$host clogin error: $_");
	    print STDERR ("$host clogin error: $_") if ($debug);
	    $clean_run = 0;
	    last;
	}
	while (/[>#]\s*($cmds_regexp)\s*$/) {
	    $cmd = $1;
	    if (!defined($prompt)) {
		# the fxos prompt is weird, see comments in fxlogin
		$prompt = "^(\[^ >]*)(>|#)";
		#$prompt = ($_ =~ /^([^#>]+[#>])/)[0];
		#$prompt =~ s/([][}{)(+\\])/\\$1/g;
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

# This routine parses "show chassis"
sub ShowChassis {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowChassis: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^$/);
	return(1) if (/Line has invalid autocommand /);
	return(1) if (/(invalid (input|command) detected|type help or )/i);

	# Ignore the PDP address and assigned DNS servers
	next if (/^pdp (ipv6 )?address/i);
	next if (/^\s*(primary|secondary) DNS (ipv6 )?address/i);

	ProcessHistory("COMMENTS","keysort","CHASSIS","! $_");
    }
    ProcessHistory("COMMENTS","keysort","CHASSIS","!\n");
    return(0);
}

# This routine parses "dir /all ((disk|slot)N|bootflash|nvram):"
sub DirSlotN {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In DirSlotN: $_" if ($debug);

    my($dev) = (/\s([^\s]+):/);

    ProcessHistory("COMMENTS","keysort","STORAGE","!\n");
    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^$/);
	return(1) if (/Line has invalid autocommand /);
	return(1) if (/(invalid (input|command) detected|type help or )/i);
	return(1) if (/(No such device|Error Sending Request)/i);
	return(1) if (/\%Error: No such file or directory/);
	return(1) if (/No space information available/);
	# Corrupt flash
	/\%Error calling getdents / &&
	    ProcessHistory("COMMENTS","keysort","STORAGE",
			   "!Flash: $dev: $_") && next;
	return(-1) if (/\%Error calling/);
	return(-1) if (/(: device being squeezed|ATA_Status time out)/i); # busy
	return(-1) if (/\%Error opening \S+:\S+ \(Device or resource busy\)/i);
	return(-1) if (/command authorization failed/i);
	return(1) if (/(Open device \S+ failed|Error opening \S+:)/);

	# 0 file(s) total size: 0 bytes
	/\d+ file.* total size: \d+/i && next;

	# filter frequently changing files (dhcp & vlan database)
	# change from:
	#    9  -rw-         660  Jan 15 2011 20:43:54 vlan.dat
	#    9  -rw-         660  Jan 15 2011 20:43:54 +00:00  vlan.dat
	# to:
	#       -rw-                                   vlan.dat
	#       -rw-                                           vlan.dat
	if (/(dhcp_[^. ]*\.txt|vlan\.dat|sflog|snooping|syslog|underlying-config)\s*$/) {
	    if (/(\s*\d+)(\s+\S+\s+)(\d+)(\s+)(\w+ \d+\s+\d+ \d+:\d+:\d+ .\d+:\d+)/) {
		my($fn, $a, $sz, $c, $dt, $rem) = ($1, $2, $3, $4, $5, $');
		my($fnl, $szl, $dtl) = (length($fn), length($sz), length($dt));
		my($fmt) = "%-". $fnl ."s%s%-". $szl ."s%s%-". $dtl ."s%s";
		$_ = sprintf($fmt, "", $a, "", $c, "", $rem);
	    } elsif (/(\s*\d+)(\s+\S+\s+)(\d+)(\s+)(\w+ \d+\s+\d+ \d+:\d+:\d+)/) {
		my($fn, $a, $sz, $c, $dt, $rem) = ($1, $2, $3, $4, $5, $');
		my($fnl, $szl, $dtl) = (length($fn), length($sz), length($dt));
		my($fmt) = "%-". $fnl ."s%s%-". $szl ."s%s%-". $dtl ."s%s";
		$_ = sprintf($fmt, "", $a, "", $c, "", $rem);
	    } elsif (/(\s*\d+)(\s+\S+\s+)(\d+)(\s+<no date>)/i) {
		# 32771  -rw-            24520                    <no date>  underlying-config
		my($fn, $a, $sz, $dt, $rem) = ($1, $2, $3, $4, $');
		my($fnl, $szl) = (length($fn), length($sz));
		my($fmt) = "%-". $fnl ."s%s%-". $szl ."s%s%s";
		$_ = sprintf($fmt, "", $a, "", $dt, $rem);
	    }
	}

	# filter frequently changing files of the config archive feature
	# change from:
	#    9  -rw-         660  Jan 15 2011 20:43:54 running-config-archive-Jul--1-16-50-27.123-113
	#    9  -rw-         660  Jan 15 2011 20:43:54 +00:00  running-config-archive-Jul--1-16-50-27.123-113
	# to:
	#       -rw-                                   running-config-archive-Jul--1-16-50-27.123-113
	#       -rw-                                           running-config-archive-Jul--1-16-50-27.123-113
	if (/(running-config-archive-)\S+\s*$/) {
	    my($arc) = $1;
	    if (/(\s*\d+)(\s+\S+\s+)(\d+)(\s+)(\w+ \d+\s+\d+ \d+:\d+:\d+ .\d+:\d+)/) {
		my($fn, $a, $sz, $c, $dt, $rem) = ($1, $2, $3, $4, $5, $');
		my($fnl, $szl, $dtl) = (length($fn), length($sz), length($dt));
		my($fmt) = "%-". $fnl ."s%s%-". $szl ."s%s%-". $dtl ."s%s%s\n";
		$_ = sprintf($fmt, "", $a, "", $c, "", $arc, "<removed>");
	    } elsif (/(\s*\d+)(\s+\S+\s+)(\d+)(\s+)(\w+ \d+\s+\d+ \d+:\d+:\d+)/) {
		my($fn, $a, $sz, $c, $dt, $rem) = ($1, $2, $3, $4, $5, $');
		my($fnl, $szl, $dtl) = (length($fn), length($sz), length($dt));
		my($fmt) = "%-". $fnl ."s%s%-". $szl ."s%s%-". $dtl ."s%s%s\n";
		$_ = sprintf($fmt, "", $a, "", $c, "", $arc, "<removed>");
	    }
	}

	if (/.*\((\d+) bytes free(\/\d+% free)?\)/) {
	    my($tmp) = $1;
	    if ($tmp >= (1024 * 1024 * 1024)) {
		$tmp = int($tmp / (1024 * 1024 * 1024));
		s/$1 bytes free/$tmp GB free/;
	    } elsif ($tmp >= (1024 * 1024)) {
		$tmp = int($tmp / (1024 * 1024));
		s/$1 bytes free/$tmp MB free/;
	    } elsif ($tmp >= (1024)) {
		$tmp = int($tmp / 1024);
		s/$1 bytes free/$tmp KB free/;
	    } elsif ($tmp > 0) {
		s/$1 bytes free/< 1KB free/;
	    } else {
		s/$1 bytes free/0 bytes free/;
	    }
	    s/\/\d+% free//;
	}
	# the pager can not be disabled per-session on the PIX
	if (/^(<-+ More -+>)/) {
	    my($len) = length($1);
	    s/^$1\s{$len}//;
	}

	ProcessHistory("COMMENTS","keysort","STORAGE","!Flash: $dev: $_");
    }
    ProcessHistory("COMMENTS","keysort","STORAGE","!\n");
    return(0);
}

# This routine parses "show firmware"
sub ShowFirmware {
    my($INPUT, $OUTPUT, $cmd) = @_;
    my($INT);
    print STDERR "    In ShowFirmware: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^$/);
	return(1) if (/(invalid (input|command) detected|type help or )/i);
	return(-1) if (/command authorization failed/i);

	ProcessHistory("COMMENTS","keysort","FIRMWARE","! $_");
    }
    return(0);
}

# This routine parses "show inventory".
sub ShowInventory {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowInventory: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	return if (/^\s*\^$/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	return(1) if (/Line has invalid autocommand /);
	next if (/^\s+\^\s*$/);
	return(1) if (/(invalid (input|command) detected|type help or )/i);
	return(-1) if (/command authorization failed/i);

	# split PID/VID/SN line
	if (/^PID: (\S*)\s*,\s*VID: (\S*)\s*,\s*SN: (\S*)\s*$/) {
	    my($pid,$vid,$sn) = ($1, $2, $3);
	    my($entries) = "";
	    # filter <empty>, "0x" and "N/A" lines
	    if ($pid !~ /^(|0x|N\/A)$/) {
		$entries .= "!PID: $pid\n";
	    }
	    if ($vid !~ /^(|0x|N\/A)$/) {
		$entries .= "!VID: $vid\n";
	    }
	    if ($sn !~ /^(|0x|N\/A)$/) {
		$entries .= "!SN: $sn\n";
	    }
	    ProcessHistory("COMMENTS","keysort","INVENTORY", "$entries");
	    next;
	}
	ProcessHistory("COMMENTS","keysort","INVENTORY","!$_");
    }
    ProcessHistory("COMMENTS","keysort","INVENTORY","!\n");

    return(0);
}

# This routine parses "show managers".
sub ShowManagers {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowManagers: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	return if (/^\s*\^$/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	return(1) if (/Line has invalid autocommand /);
	next if (/^\s+\^\s*$/);
	return(1) if (/(invalid (input|command) detected|type help or )/i);
	return(-1) if (/command authorization failed/i);

	ProcessHistory("COMMENTS","keysort","NETWORK","! $_");
    }
    ProcessHistory("COMMENTS","keysort","NETWORK","!\n");

    return(0);
}

# This routine parses "show mode".
sub ShowMode {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowMode: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	return if (/^\s*\^$/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	return(1) if (/Line has invalid autocommand /);
	next if (/^\s+\^\s*$/);
	return(1) if (/(invalid (input|command) detected|type help or )/i);
	return(-1) if (/command authorization failed/i);

	ProcessHistory("COMMENTS","keysort","MODE","!MODE: $_");
    }
    ProcessHistory("COMMENTS","keysort","MODE","!\n");

    return(0);
}

# This routine parses "show model".
sub ShowModel {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowModel: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	return if (/^\s*\^$/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	return(1) if (/Line has invalid autocommand /);
	next if (/^\s+\^\s*$/);
	return(1) if (/(invalid (input|command) detected|type help or )/i);
	return(-1) if (/command authorization failed/i);

	/(cisco.*)/i &&
	    ProcessHistory("COMMENTS","keysort","A1", "!Chassis type: $1\n") &&
	    next;

	ProcessHistory("COMMENTS","keysort","A5","!$_");
    }
    ProcessHistory("COMMENTS","keysort","A9","!\n");

    return(0);
}

# This routine parses "show network".
sub ShowNetwork {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowNetwork: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	return if (/^\s*\^$/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	return(1) if (/Line has invalid autocommand /);
	next if (/^\s+\^\s*$/);
	return(1) if (/(invalid (input|command) detected|type help or )/i);
	return(-1) if (/command authorization failed/i);

	ProcessHistory("COMMENTS","keysort","NETWORK","!$_");
    }
    ProcessHistory("COMMENTS","keysort","NETWORK","!\n");

    return(0);
}

# This routine processes a "write term" for the FTD layer
sub WriteTermFTD {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In WriteTermFTD: $_" if ($debug);
    my($comment, $linecnt, $ftd_end) = (0, 0, 0);

    while (<$INPUT>) {
TOP:
	tr/\015//d;
	last if (/^$prompt/);
	return(1) if (!$linecnt && /^\s+\^\s*$/);
	next if (/^\s*$cmd\s*$/);
	return(1) if (/Line has invalid autocommand /);
	next if (/^\s+\^\s*$/);
	return(1) if (/(invalid (input|command) detected|type help or )/i);
	return(1) if (/\%Error: No such file or directory/);
	return(1) if (/(Open device \S+ failed|Error opening \S+:)/);
	return(0) if ($found_end);		# Only do this routine once
	return(-1) if (/command authorization failed/i);
	return(-1) if (/% ?configuration buffer full/i);

	/^! no configuration change since last restart/i && next;
	# skip emtpy lines at the beginning
	if (!$linecnt && /^\s*$/) {
	    next;
	}

	/Non-Volatile memory is in use/ && return(-1); # NvRAM is locked
	/% Configuration buffer full, / && return(-1); # buffer is in use
	$linecnt++;
	# skip the crap
	/^:( written by \S+ at| saved| $|$)/i && next;
	/^ngfw version /i && next;

	# skip consecutive comment lines to avoid oscillating extra comment
	# line on some access servers.  grrr.
	if (/^!\s*$/) {
	    next if ($comment);
	    ProcessHistory("COMMENTS","keysort","Z1",$_);
	    $comment++;
	    next;
	}
	$comment = 0;

	# why put h/w info in show chassis something or other when you could
	# put it in show running-config?
	# : Serial Number: JAD59721NNU
	# : Hardware:   FPR-2110, 6842 MB RAM, CPU MIPS 1200 MHz, 1 CPU (6 cores)
	/^: ((serial number|hardware): .*)/i &&
	    ProcessHistory("COMMENTS","keysort","A1","!$1\n") && next;

	# Dog gone Cool matches to process the rest of the config
	/^tftp-server flash /   && next; # kill any tftp remains
	/^ntp clock-period /    && next; # kill ntp clock-period
	/^ clockrate /		&& next; # kill clockrate on serial interfaces
	# kill rx/txspeed (particularly on cellular modem cards)
	if (/^(line (\d+(\/\d+\/\d+)?|con|aux|vty))/) {
	    my($key) = $1;
	    my($lineauto) = (0);
	    if ($key =~ /con/) {
		$key = -1;
	    } elsif ($key =~ /aux/) {
		$key = -2;
	    } elsif ($key =~ /vty/) {
		$key = -3;
	    }
	    ProcessHistory("COMMENTS","keysort","Z1","$_");
	    while (<$INPUT>) {
		tr/\015//d;
		last if (/^$prompt/);
		goto TOP if (! /^ /);
		next if (/\s*(rx|tx)speed \d+/);
		next if (/^ length /);	# kill length on serial lines
		next if (/^ width /);	# kill width on serial lines
		$lineauto = 0 if (/^[^ ]/);
		$lineauto = 1 if /^ modem auto/;
		/^ speed / && $lineauto	&& next; # kill speed on serial lines
		if (/^(\s+password) \d+ / && $filter_pwds >= 1) {
		    $_ = "!$1 <removed>\n";
		}
		ProcessHistory("COMMENTS","keysort","Z1","$_");
	    }
	}
	if (/^(enable )?(password|passwd)( level \d+)? / && $filter_pwds >= 1) {
	    ProcessHistory("COMMENTS","keysort","Z1","!$1$2$3 <removed>\n");
	    next;
	}
	if (/^(enable secret) / && $filter_pwds >= 2) {
	    ProcessHistory("COMMENTS","keysort","Z1","!$1 <removed>\n");
	    next;
	}
	if (/^username (\S+)(\s.*)? secret /) {
	    if ($filter_pwds >= 2) {
		ProcessHistory("COMMENTS","keysort","Z1",
			       "!username $1$2 secret <removed>\n");
	    } else {
		ProcessHistory("COMMENTS","keysort","Z1","$_");
	    }
	    next;
	}
	if (/^username (\S+)(\s.*)? password ((\d) \S+|\S+)/) {
	    if ($filter_pwds >= 2) {
		ProcessHistory("COMMENTS","keysort","Z1",
			       "!username $1$2 password <removed>\n");
	    } elsif ($filter_pwds >= 1 && $4 ne "5"){
		ProcessHistory("COMMENTS","keysort","Z1",
			       "!username $1$2 password <removed>\n");
	    } else {
		ProcessHistory("COMMENTS","keysort","Z1", "$_");
	    }
	    next;
	}
	if (/^(\s*)password / && $filter_pwds >= 1) {
	    ProcessHistory("COMMENTS","keysort","Z1","!$1password <removed>\n");
	    next;
	}
	if (/^(\s*)secret / && $filter_pwds >= 2) {
	    ProcessHistory("COMMENTS","keysort","Z1","!$1secret <removed>\n");
	    next;
	}
	if (/^(ip ftp password) / && $filter_pwds >= 1) {
	    ProcessHistory("COMMENTS","keysort","Z1","!$1 <removed>\n"); next;
	}
	if (/^( ip ospf authentication-key) / && $filter_pwds >= 1) {
	    ProcessHistory("COMMENTS","keysort","Z1","!$1 <removed>\n"); next;
	}
	if (/^\s+(domain-password|area-password) (\S+)( .*)?/
	    && $filter_pwds >= 1) {
	    ProcessHistory("COMMENTS","keysort","Z1","!$1 <removed>$3\n"); next;
	}
	# this is reversable, despite 'md5' in the cmd
	if (/^( ip ospf message-digest-key \d+ md5) / && $filter_pwds >= 1) {
	    ProcessHistory("COMMENTS","keysort","Z1","!$1 <removed>\n"); next;
	}
	# this is also reversable, despite 'md5 encrypted' in the cmd
	if (/^(  message-digest-key \d+ md5 (7|encrypted)) /
	    && $filter_pwds >= 1) {
	    ProcessHistory("COMMENTS","keysort","Z1","!$1 <removed>\n"); next;
	}
	if (/^((crypto )?isakmp key) (\d )?\S+ / && $filter_pwds >= 1) {
	    ProcessHistory("COMMENTS","keysort","Z1","!$1 <removed> $'"); next;
	}
	# filter HSRP passwords
	if (/^(\s+standby \d+ authentication) / && $filter_pwds >= 1) {
	    ProcessHistory("COMMENTS","keysort","Z1","!$1 <removed>\n"); next;
	}
	# ASA/PIX keys in more system:running-config
	if (/^(( ikev2)? (local|remote)-authentication pre-shared-key ).*/ &&
	    $filter_pwds >= 1) {
	    ProcessHistory("COMMENTS","keysort","Z1","!$1 <removed> $'"); next;
	}
	# ASA/PIX keys in more system:running-config
	if (/^(( ikev1)? pre-shared-key | key |failover key ).*/ &&
	    $filter_pwds >= 1) {
	    ProcessHistory("COMMENTS","keysort","Z1","!$1 <removed> $'"); next;
	}
	# ASA/PIX keys in more system:running-config
	if (/(\s+ldap-login-password )\S+(.*)/ && $filter_pwds >= 1) {
	    ProcessHistory("COMMENTS","keysort","Z1","!$1 <removed> $'"); next;
	}
	/fair-queue individual-limit/ && next;
	# filter out any RCS/CVS tags to avoid confusing local CVS storage
	s/\$(Revision|Id):/ $1:/;
	# order/prune snmp-server host statements
	# we only prune lines of the form
	# snmp-server host a.b.c.d <community>
	if (/^snmp-server host (\d+\.\d+\.\d+\.\d+) /) {
	    if ($filter_commstr) {
		my($ip) = $1;
		my($line) = "snmp-server host $ip";
		my(@tokens) = split(' ', $');
		my($token);
		while ($token = shift(@tokens)) {
		    if ($token eq 'version') {
			$line .= " " . join(' ', ($token, shift(@tokens)));
			if ($token eq '3') {
			    $line .= " " . join(' ', ($token, shift(@tokens)));
			}
		    } elsif ($token eq 'vrf') {
			$line .= " " . join(' ', ($token, shift(@tokens)));
		    } elsif ($token =~ /^(informs?|traps?|(no)?auth)$/) {
			$line .= " " . $token;
		    } else {
			$line = "!$line " . join(' ', ("<removed>",
						 join(' ',@tokens)));
			last;
		    }
		}
		ProcessHistory("COMMENTS","keysort","Z1","$line\n");
	    } else {
		ProcessHistory("COMMENTS","keysort","Z1","$_");
	    }
	    next;
	}
	# For ASA version 8.x and higher, the format changed a little. It is
	# 'snmp-server host {interface {hostname | ip_address}} [trap | poll]
	# [community  0 | 8 community-string] [version {1 | 2c | 3 username}]
	# [udp-port port] '
	if (/^(snmp-server .*community) ([08] )?(\S+)/) {
	    if ($filter_commstr) {
		ProcessHistory("COMMENTS","keysort","Z1",
			       "!$1 <removed>$'") && next;
	    } else {
		ProcessHistory("COMMENTS","keysort","Z1","$_") && next;
	    }
	}
	# prune tacacs/radius server keys
	if (/^((tacacs|radius)-server\s(\w*[-\s(\s\S+])*\s?key) (\d )?\S+/
	    && $filter_pwds >= 1) {
	    ProcessHistory("COMMENTS","keysort","Z1","!$1 <removed>$'"); next;
	}
	# delete ntp auth password - this md5 is a reversable too
	if (/^(ntp authentication-key \d+ md5) / && $filter_pwds >= 1) {
	    ProcessHistory("COMMENTS","keysort","Z1","!$1 <removed>\n"); next;
	}

	/^ *Cryptochecksum:/ && next;

	# catch anything that wasnt matched above.
	ProcessHistory("COMMENTS","keysort","Z1","$_");
	# end of config.
	if (/^: +end$/) {
	    $ftd_end = 1;
	    return(0);
	}
    }
    # The ContentEngine lacks a definitive "end of config" marker.  If we
    # know that it is a CE, SAN, or NXOS and we have seen at least 5 lines
    # of write term output, we can be reasonably sure that we have the config.
    if (! $ftd_end) {
	return(-1);
    }

    return(0);
}

# This routine processes a "write term"
sub WriteTerm {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In WriteTerm: $_" if ($debug);
    my($comment, $linecnt) = (0, 0);

    ProcessHistory("","","","!\n!\n");
    while (<$INPUT>) {
TOP:
	tr/\015//d;
	last if (/^$prompt/);
	return(1) if (!$linecnt && /^\s+\^\s*$/);
	next if (/^\s*$cmd\s*$/);
	return(1) if (/Line has invalid autocommand /);
	next if (/^\s+\^\s*$/);
	return(1) if (/(invalid (input|command) detected|type help or )/i);
	return(1) if (/\%Error: No such file or directory/);
	return(1) if (/(Open device \S+ failed|Error opening \S+:)/);
	return(0) if ($found_end);		# Only do this routine once
	return(-1) if (/command authorization failed/i);
	return(-1) if (/% ?configuration buffer full/i);
	# the pager can not be disabled per-session on the PIX
	if (/^(<-+ More -+>)/) {
	    my($len) = length($1);
	    s/^$1\s{$len}//;
	}
	/^! no configuration change since last restart/i && next;
	# skip emtpy lines at the beginning
	if (!$linecnt && /^\s*$/) {
	    next;
	}

	/Non-Volatile memory is in use/ && return(-1); # NvRAM is locked
	/% Configuration buffer full, / && return(-1); # buffer is in use
	$linecnt++;
	# skip the crap
	if (/^(##+|(building|current) configuration)/i) {
	    while (<$INPUT>) {
		next if (/^Current configuration\s*:/i);
		next if (/^:/);
		next if (/^([%!].*|\s*)$/);
		next if (/^ip add.*ipv4:/);	# band-aid for 3620 12.0S
		last;
	    }
	    tr/\015//d;
	}
	# config timestamp on MDS/NX-OS
	/Time: / && next;
	# skip ASA 5520 configuration author line
	/^: written by /i && next;
	# some versions have other crap mixed in with the bits in the
	# block above
	/^! (Last configuration|NVRAM config last)/ && next;
	# and for the ASA
	/^: (Written by \S+ at|Saved)/ && next;

	# skip consecutive comment lines to avoid oscillating extra comment
	# line on some access servers.  grrr.
	if (/^!\s*$/) {
	    next if ($comment);
	    ProcessHistory("","","",$_);
	    $comment++;
	    next;
	}
	$comment = 0;

	# Dog gone Cool matches to process the rest of the config
	/^tftp-server flash /   && next; # kill any tftp remains
	/^ntp clock-period /    && next; # kill ntp clock-period
	/^ clockrate /		&& next; # kill clockrate on serial interfaces
	# kill rx/txspeed (particularly on cellular modem cards)
	if (/^(line (\d+(\/\d+\/\d+)?|con|aux|vty))/) {
	    my($key) = $1;
	    my($lineauto) = (0);
	    if ($key =~ /con/) {
		$key = -1;
	    } elsif ($key =~ /aux/) {
		$key = -2;
	    } elsif ($key =~ /vty/) {
		$key = -3;
	    }
	    ProcessHistory("LINE","keysort","$key","$_");
	    while (<$INPUT>) {
		tr/\015//d;
		last if (/^$prompt/);
		goto TOP if (! /^ /);
		next if (/\s*(rx|tx)speed \d+/);
		next if (/^ length /);	# kill length on serial lines
		next if (/^ width /);	# kill width on serial lines
		$lineauto = 0 if (/^[^ ]/);
		$lineauto = 1 if /^ modem auto/;
		/^ speed / && $lineauto	&& next; # kill speed on serial lines
		if (/^(\s+password) \d+ / && $filter_pwds >= 1) {
		    $_ = "!$1 <removed>\n";
		}
		ProcessHistory("LINE","keysort","$key","$_");
	    }
	}
	if (/^(enable )?(password|passwd)( level \d+)? / && $filter_pwds >= 1) {
	    ProcessHistory("ENABLE","","","!$1$2$3 <removed>\n");
	    next;
	}
	if (/^(enable secret) / && $filter_pwds >= 2) {
	    ProcessHistory("ENABLE","","","!$1 <removed>\n");
	    next;
	}
	if (/^username (\S+)(\s.*)? secret /) {
	    if ($filter_pwds >= 2) {
		ProcessHistory("USER","keysort","$1",
			       "!username $1$2 secret <removed>\n");
	    } else {
		ProcessHistory("USER","keysort","$1","$_");
	    }
	    next;
	}
	if (/^username (\S+)(\s.*)? password ((\d) \S+|\S+)/) {
	    if ($filter_pwds >= 2) {
		ProcessHistory("USER","keysort","$1",
			       "!username $1$2 password <removed>\n");
	    } elsif ($filter_pwds >= 1 && $4 ne "5"){
		ProcessHistory("USER","keysort","$1",
			       "!username $1$2 password <removed>\n");
	    } else {
		ProcessHistory("USER","keysort","$1","$_");
	    }
	    next;
	}
	# cisco AP w/ IOS
	if (/^(wlccp \S+ username (\S+)(\s.*)? password) (\d \S+|\S+)/) {
	    if ($filter_pwds >= 1) {
		ProcessHistory("USER","keysort","$2","!$1 <removed>\n");
	    } else {
		ProcessHistory("USER","keysort","$2","$_");
	    }
	    next;
	}
	# filter auto "rogue ap" configuration lines
	/^rogue ap classify / && next;
	if (/^( set session-key (in|out)bound ah \d+ )/ && $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1<removed>\n");
	    next;
	}
	if (/^( set session-key (in|out)bound esp \d+ (authenticator|cypher) )/
	    && $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1<removed>\n");
	    next;
	}
	if (/^(\s*)password / && $filter_pwds >= 1) {
	    ProcessHistory("LINE-PASS","","","!$1password <removed>\n");
	    next;
	}
	if (/^(\s*)secret / && $filter_pwds >= 2) {
	    ProcessHistory("LINE-PASS","","","!$1secret <removed>\n");
	    next;
	}
	if (/^\s*(.*?neighbor.*?) (\S*) password / && $filter_pwds >= 1) {
	    ProcessHistory("","","","! $1 $2 password <removed>\n");
	    next;
	}
	if (/^(\s*ppp .* hostname) .*/ && $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1 <removed>\n"); next;
	}
	if (/^(\s*ppp .* password) \d .*/ && $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1 <removed>\n"); next;
	}
	if (/^(ip ftp password) / && $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1 <removed>\n"); next;
	}
	if (/^( ip ospf authentication-key) / && $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1 <removed>\n"); next;
	}
	# isis passwords appear to be completely plain-text
	if (/^\s+isis password (\S+)( .*)?/ && $filter_pwds >= 1) {
	    ProcessHistory("","","","!isis password <removed>$2\n"); next;
	}
	if (/^\s+(domain-password|area-password) (\S+)( .*)?/
							&& $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1 <removed>$3\n"); next;
	}
	# this is reversable, despite 'md5' in the cmd
	if (/^( ip ospf message-digest-key \d+ md5) / && $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1 <removed>\n"); next;
	}
	# this is also reversable, despite 'md5 encrypted' in the cmd
	if (/^(  message-digest-key \d+ md5 (7|encrypted)) /
	    && $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1 <removed>\n"); next;
	}
	if (/^((crypto )?isakmp key) (\d )?\S+ / && $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1 <removed> $'"); next;
	}
	# filter HSRP passwords
	if (/^(\s+standby \d+ authentication) / && $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1 <removed>\n"); next;
	}
	# this appears in "measurement/sla" images
	if (/^(\s+key-string \d?)/ && $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1 <removed>\n"); next;
	}
	if (/^( l2tp tunnel \S+ password)/ && $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1 <removed>\n"); next;
	}
	# l2tp-class secret
	if (/^( digest secret 7?)/ && $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1 <removed>\n"); next;
	}
	# i am told these are plain-text on the PIX
	if (/^(vpdn username (\S+) password)/) {
	    if ($filter_pwds >= 1) {
		ProcessHistory("USER","keysort","$2","!$1 <removed>\n");
	    } else {
		ProcessHistory("USER","keysort","$2","$_");
	    }
	    next;
	}
	# ASA/PIX keys in more system:running-config
	if (/^(( ikev2)? (local|remote)-authentication pre-shared-key ).*/ &&
	    $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1 <removed> $'"); next;
	}
	# ASA/PIX keys in more system:running-config
	if (/^(( ikev1)? pre-shared-key | key |failover key ).*/ &&
	    $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1 <removed> $'"); next;
	}
	# ASA/PIX keys in more system:running-config
	if (/(\s+ldap-login-password )\S+(.*)/ && $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1 <removed> $'"); next;
	}
	# filter WPA password such as on cisco 877W ISR
	if (/^\s+(wpa-psk ascii|hex \d) / && $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1 <removed>\n"); next;
	}
	#
	if (/^( cable shared-secret )/ && $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1 <removed>\n");
	    next;
	}
	/fair-queue individual-limit/ && next;
	# sort ip explicit-paths.
	if (/^ip explicit-path name (\S+)/) {
	    my($key) = $1;
	    my($expath) = $_;
	    while (<$INPUT>) {
		tr/\015//d;
		last if (/^$prompt/);
		last if (/^$prompt/ || ! /^(ip explicit-path name |[ !])/);
		if (/^ip explicit-path name (\S+)/) {
		    ProcessHistory("EXPATH","keysort","$key","$expath");
		    $key = $1;
		    $expath = $_;
		} else  {
		    $expath .= $_;
		}
	    }
	    ProcessHistory("EXPATH","keysort","$key","$expath");
	}
	# sort route-maps
	if (/^route-map (\S+)/) {
	    my($key) = $1;
	    my($routemap) = $_;
	    while (<$INPUT>) {
		tr/\015//d;
		last if (/^$prompt/ || ! /^(route-map |[ !])/);
		if (/^route-map (\S+)/) {
		    ProcessHistory("ROUTEMAP","keysort","$key","$routemap");
		    $key = $1;
		    $routemap = $_;
		} else  {
		    $routemap .= $_;
		}
	    }
	    ProcessHistory("ROUTEMAP","keysort","$key","$routemap");
	}
	# filter out any RCS/CVS tags to avoid confusing local CVS storage
	s/\$(Revision|Id):/ $1:/;
	# order access-lists
	/^access-list\s+(\d\d?)\s+(\S+)\s+(\S+)/ &&
	    ProcessHistory("ACL $1 $2","$aclsort","$3","$_") && next;
	# order extended access-lists
	if ($aclfilterseq) {
	/^access-list\s+(\d\d\d)\s+(\S+)\s+(\S+)\s+host\s+(\S+)/ &&
	    ProcessHistory("EACL $1 $2","$aclsort","$4","$_") && next;
	/^access-list\s+(\d\d\d)\s+(\S+)\s+(\S+)\s+(\d\S+)/ &&
	    ProcessHistory("EACL $1 $2","$aclsort","$4","$_") && next;
	/^access-list\s+(\d\d\d)\s+(\S+)\s+(\S+)\s+any/ &&
	    ProcessHistory("EACL $1 $2","$aclsort","0.0.0.0","$_") && next;
	}
	if ($aclfilterseq) {
	    /^ip(v6)? prefix-list\s+(\S+)\s+seq\s+(\d+)\s+(permit|deny)\s+(\S+)(.*)/
		&& ProcessHistory("PACL $2 $4","$aclsort","$5",
				  "ip$1 prefix-list $2 $4 $5$6\n")
		&& next;
	}
	# sort ipv{4,6} access-lists
	if ($aclfilterseq && /^ipv(4|6) access-list (\S+)\s*$/) {
	    my($nlri, $key) = ($1, $2);
	    my($seq, $cmd);
	    ProcessHistory("ACL $nlri $key","","","$_");
	    while (<$INPUT>) {
		tr/\015//d;
		last if (/^$prompt/ || /^\S/);
		# ipv4 access-list name
		#  remark NTP
   		#  deny ipv4 host 224.0.1.1 any
		#  deny ipv4 239.0.0.0 0.255.255.255 any
		#  permit udp any eq 123 any
		#  permit ipv4 nnn.nnn.nnn.nnn/nn any
		#  permit nnn.nnn.nnn.nnn/nn
		# ipv6 access-list name
		#  permit ipv6 host 2001:nnnn::nnnn any
		#  permit ipv6 2001:nnn::/nnn any
		#  permit 2001:nnnn::/64 any
		#  permit udp any eq 123 any
		#
		# line might begin with " sequence nnn permit ..."
		s/^\s+(sequence (\d+)) / /;
		my($seq) = $1;
		my($cmd, $resid) = ($_ =~ /^\s+(\w+) (.+)/);
		if ($cmd =~ /(permit|deny)/) {
		    my($ip);
		    my(@w) = ($resid =~ /(\S+) (\S+) (\S+\s)?(.+)/);
		    for (my($i) = 0; $i < $#w; $i++) {
			if ($w[$i] eq "any") {
			    if ($nlri eq "ipv4") {
				$ip = "255.255.255.255/32";
			    } else {
				$ip = "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff/128";
			    }
			    last;
			} elsif ($w[$i] =~ /^[:0-9]/ ||
				 $2[$i] =~ /^[a-fA-F]{1,4}:/) {
			    $ip = $w[$i];
			    $ip =~ s/\s+$//;		# trim trailing WS
			    last;
			}
		    }
		    ProcessHistory("ACL $nlri $key $cmd", "$aclsort", "$ip",
				   " $cmd $resid\n");
		} else {
		    ProcessHistory("ACL $nlri $key $cmd", "", "",
				   " $cmd $resid\n");
		}
	    }
	}
	# order arp lists
	/^arp\s+(\d+\.\d+\.\d+\.\d+)\s+/ &&
	    ProcessHistory("ARP","$aclsort","$1","$_") && next;
	# order logging statements
	/^logging (\d+\.\d+\.\d+\.\d+)/ &&
	    ProcessHistory("LOGGING","ipsort","$1","$_") && next;
	# order/prune snmp-server host statements
	# we only prune lines of the form
	# snmp-server host a.b.c.d <community>
	if (/^snmp-server host (\d+\.\d+\.\d+\.\d+) /) {
	    if ($filter_commstr) {
		my($ip) = $1;
		my($line) = "snmp-server host $ip";
		my(@tokens) = split(' ', $');
		my($token);
		while ($token = shift(@tokens)) {
		    if ($token eq 'version') {
			$line .= " " . join(' ', ($token, shift(@tokens)));
			if ($token eq '3') {
			    $line .= " " . join(' ', ($token, shift(@tokens)));
			}
		    } elsif ($token eq 'vrf') {
			$line .= " " . join(' ', ($token, shift(@tokens)));
		    } elsif ($token =~ /^(informs?|traps?|(no)?auth)$/) {
			$line .= " " . $token;
		    } else {
			$line = "!$line " . join(' ', ("<removed>",
						 join(' ',@tokens)));
			last;
		    }
		}
		ProcessHistory("SNMPSERVERHOST","ipsort","$ip","$line\n");
	    } else {
		ProcessHistory("SNMPSERVERHOST","ipsort","$1","$_");
	    }
	    next;
	}
	# For ASA version 8.x and higher, the format changed a little. It is
	# 'snmp-server host {interface {hostname | ip_address}} [trap | poll]
	# [community  0 | 8 community-string] [version {1 | 2c | 3 username}]
	# [udp-port port] '
	if (/^(snmp-server .*community) ([08] )?(\S+)/) {
	    if ($filter_commstr) {
		ProcessHistory("SNMPSERVERCOMM","keysort","$_",
			       "!$1 <removed>$'") && next;
	    } else {
		ProcessHistory("SNMPSERVERCOMM","keysort","$_","$_") && next;
	    }
	}
	# prune tacacs/radius server keys
	if (/^((tacacs|radius)-server\s(\w*[-\s(\s\S+])*\s?key) (\d )?\S+/
	    && $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1 <removed>$'"); next;
	}
	# order clns host statements
	/^clns host \S+ (\S+)/ &&
	    ProcessHistory("CLNS","keysort","$1","$_") && next;
	# order alias statements
	/^alias / && ProcessHistory("ALIAS","keysort","$_","$_") && next;
	# delete ntp auth password - this md5 is a reversable too
	if (/^(ntp authentication-key \d+ md5) / && $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1 <removed>\n"); next;
	}
	# order ntp peers/servers
	if (/^ntp (server|peer) (\d+)\.(\d+)\.(\d+)\.(\d+)/) {
	    my($sortkey) = sprintf("$1 %03d%03d%03d%03d",$2,$3,$4,$5);
	    ProcessHistory("NTP","keysort",$sortkey,"$_");
	    next;
	}
	# order ip host statements
	/^ip host (\S+) / &&
	    ProcessHistory("IPHOST","keysort","$1","$_") && next;
	# order ip nat source static statements
	/^ip nat (\S+) source static (\S+)/ &&
	    ProcessHistory("IP NAT $1","ipsort","$2","$_") && next;

	# system controller
	/^syscon address (\S*) (\S*)/ &&
	    ProcessHistory("","","","!syscon address $1 <removed>\n") &&
	    next;
	if (/^syscon password (\S*)/ && $filter_pwds >= 1) {
	    ProcessHistory("","","","!syscon password <removed>\n");
	    next;
	}

	/^ *Cryptochecksum:/ && next;

	# catch anything that wasnt matched above.
	ProcessHistory("","","","$_");
	# end of config.  the ": " game is for the PIX
	if (/^(: +)?end$/) {
	    $found_end = 1;
	    return(0);
	}
    }
    # The ContentEngine lacks a definitive "end of config" marker.  If we
    # know that it is a CE, SAN, or NXOS and we have seen at least 5 lines
    # of write term output, we can be reasonably sure that we have the config.
    if ($linecnt > 5) {
	$found_end = 1;
	return(0);
    }

    return(0);
}

1;
