package junos;
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
#  junos.pm - Juniper JunOS rancid procedures
#

use 5.010;
use strict 'vars';
use warnings;
require(Exporter);
our @ISA = qw(Exporter);
$Exporter::Verbose=1;

use rancid 3.12;

our $ShowChassisSCB;			# Only run ShowChassisSCB() once
our $ShowChassisFirmware;		# Only run ShowChassisFirmware() once


@ISA = qw(Exporter rancid main);
#our @EXPORT = qw($VERSION)

# load-time initialization
sub import {
    0;
}

# post-open(collection file) initialization
sub init {
    # add content lines and separators
    ProcessHistory("","","","#RANCID-CONTENT-TYPE: $devtype\n#\n");

    $junos::ShowChassisFirmware = 0;
    0;
}

# main loop of input of device output
sub inloop {
    my($INPUT, $OUTPUT) = @_;
    my($cmd, $rval);

TOP: while (<$INPUT>) {
	tr/\015//d;
	if (/^Error:/) {
	    print STDOUT ("$host jlogin error: $_");
	    print STDERR ("$host jlogin error: $_") if ($debug);
	    $clean_run = 0;
	    last;
	}
	if (/System shutdown message/) {
	    print STDOUT ("$host shutdown msg: $_");
	    print STDERR ("$host shutdown msg: $_") if ($debug);
	    $clean_run = 0;
	    last;
	}
	if (/error: cli version does not match Managment Daemon/i) {
	    print STDOUT ("$host mgd version mismatch: $_");
	    print STDERR ("$host mgd version mismatch: $_") if ($debug);
	    $clean_run = 0;
	    last;
	}
	while (/>\s*($cmds_regexp)\s*$/) {
	    $cmd = $1;
	    if (!defined($prompt)) {
		$prompt = ($_ =~ /^([^>]+>)/)[0];
		$prompt =~ s/([][}{)(\\])/\\$1/g;
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
	if (/>\s*quit/) {
	    $clean_run = 1;
	    last;
	}
    }
}

# This routine parses "show chassis clocks"
sub ShowChassisClocks {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowChassisClocks: $_" if ($debug);

    s/^[a-z]+@//;
    ProcessHistory("","","","# $_");
    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^system (shutdown message from|going down )/i);
	next if (/^\{(master|backup|linecard|primary|secondary)(:(node)?\d+)?\}/);

	/error: the chassis(-control)? subsystem is not r/ && return(-1);
	/error: abnormal communication termination with / && return(-1);
	/error: invalid xml tag / && return(-1);
	/Couldn\'t initiate connection/ && return(-1);
	/Unrecognized command/ && return(1);
	/command is not valid/ && return(1);
	/^\s+\^/ && return(1);
	/syntax error/ && return(1);

	# filter decimal places of m160 measured clock MHz
	if (/Measured frequency/) {
	    s/\..*MHz/ MHz/;
	} elsif (/^.+\.[0-9]+ MHz$/) {
	    # filter for the m160 (newer format)
	    s/\.[0-9]+ MHz/ MHz/;
	} elsif (/^(.+)(\.[0-9]+) MHz/) {
	    # filter for T series
	    my($leadlen) = length($1);
	    my($x);
	    $x = sprintf(" MHz%".length($2)."s", " ");
	    substr($_, $leadlen, length($2)+4, $x);
	}
	# filter timestamps
	next if (/selected for/i);
	next if (/selected since/i);

	next if (/deviation/i);
	ProcessHistory("","","","# $_");
    }
    return(0);
}

# This routine parses "show chassis environment"
sub ShowChassisEnvironment {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowChassisEnvironment: $_" if ($debug);

    s/^[a-z]+@//;
    ProcessHistory("","","","# $_");
    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	return 1 if (/^aborted!/i);
	next if (/^system (shutdown message from|going down )/i);
	next if (/^\{(master|backup|linecard|primary|secondary)(:(node)?\d+)?\}/);

	/error: the chassis(-control)? subsystem is not r/ && return(-1);
	/Couldn\'t initiate connection/ && return(-1);
	/Unrecognized command/ && return(1);
	/command is not valid/ && return(1);
	/^\s+\^/ && return(1);
	/syntax error/ && return(1);

	/ backplane temperature/ && next;
	/(\s*Power supply.*), temperature/ &&
		ProcessHistory("","","","# $1\n") && next;
	/(\s*.+) +-?\d+ degrees C.*$/ &&
		ProcessHistory("","","","# $1\n") && next;
	/(^.*\S)\s+ Spinning at .*$/ &&
		ProcessHistory("","","","# $1\n") && next;
	/(^.*\S)\s+ \d+ RPM$/ &&
		ProcessHistory("","","","# $1\n") && next;
	/(^.*\S)\s+Measurement/ &&
		ProcessHistory("","","","# $1\n") && next;
	ProcessHistory("","","","# $_");
    }
    return(0);
}

# This routine parses "show chassis firmware"
sub ShowChassisFirmware {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowChassisFirmware: $_" if ($debug);

    s/^[a-z]+@//;
    ProcessHistory("","","","# $_");
    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	return(1) if (/^aborted!/i);
	next if (/^system (shutdown message from|going down )/i);
	next if (/^\{(master|backup|linecard|primary|secondary)(:(node)?\d+)?\}/);

	return(0) if ($junos::ShowChassisFirmware);
	/error: the chassis(-control)? subsystem is not r/ && return(-1);
	/Couldn\'t initiate connection/ && return(-1);
	/Unrecognized command/ && return(1);
	/command is not valid/ && return(1);
	/^\s+\^/ && return(1);
	/syntax error/ && return(1);

	s/\s*$//;
	ProcessHistory("","","","# $_\n");
    }
    $ShowChassisFirmware = 1;
    return(0);
}

# This routine parses "show chassis fpc detail"
sub ShowChassisFpcDetail {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowChassisFpcDetail: $_" if ($debug);

    s/^[a-z]+@//;
    ProcessHistory("","","","# $_");
    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	return 1 if (/^aborted!/i);
	next if (/^system (shutdown message from|going down )/i);
	next if (/^\{(master|backup|linecard|primary|secondary)(:(node)?\d+)?\}/);

	/error: the chassis(-control)? subsystem is not r/ && return(-1);
	/Couldn\'t initiate connection/ && return(-1);
	/Unrecognized command/ && return(1);
	/command is not valid/ && return(1);
	/^\s+\^/ && return(1);
	/syntax error/ && return(1);

	/ Temperature/ && next;
	/ Start time/ && next;
	/ Uptime/ && next;
	ProcessHistory("","","","# $_");
    }
    return(0);
}

# This routine parses "show chassis hardware"
sub ShowChassisHardware {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowChassisHardware: $_" if ($debug);

    s/^[a-z]+@//;
    ProcessHistory("","","","# $_");
    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	return 1 if (/^aborted!/i);
	next if (/^system (shutdown message from|going down )/i);
	next if (/^\{(master|backup|linecard|primary|secondary)(:(node)?\d+)?\}/);

	/error: the chassis(-control)? subsystem is not r/ && return(-1);
	/Couldn\'t initiate connection/ && return(-1);
	/Unrecognized command/ && return(1);
	/command is not valid/ && return(1);
	/^\s+\^/ && return(1);
	/syntax error/ && return(1);

	ProcessHistory("","","","# $_");
    }
    return(0);
}

# This routine parses "show chassis routing-engine"
# Most output is ignored.
sub ShowChassisRoutingEngine {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowChassisRoutingEngine: $_" if ($debug);

    s/^[a-z]+@//;
    ProcessHistory("","","","# $_");
    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^system (shutdown message from|going down )/i);
	next if (/^\{(master|backup|linecard|primary|secondary)(:(node)?\d+)?\}/);

	/error: the chassis(-control)? subsystem is not r/ && return(-1);
	/Couldn\'t initiate connection/ && return(-1);
	/Unrecognized command/ && return(1);
	/command is not valid/ && return(1);
	/^\s+\^/ && return(1);
	/syntax error/ && return(1);

	/^Routing Engine status:/ && ProcessHistory("","","","# $_") && next;
	/ Slot / && ProcessHistory("","","","# $_") && next;
	/ Current state/ && ProcessHistory("","","","# $_") && next;
	/ Election priority/ && ProcessHistory("","","","# $_") && next;
	s/ (DRAM\s+)\d+ \w+ \((\d+ \w+) installed\)\s*/ $1$2\n/
		&& ProcessHistory("","","","# $_") && next;
	/ DRAM/ && ProcessHistory("","","","# $_") && next;
	/ Model/ && ProcessHistory("","","","# $_") && next;
	/ Serial ID/ && ProcessHistory("","","","# $_") && next;
	/^\s*$/ && ProcessHistory("","","","# $_") && next;
    }
    return(0);
}

# This routine parses "show chassis cfeb", "show chassis feb", "show
# chassis scb", "show chassis sfm detail", and "show chassis ssb".
# Only do this routine once.
sub ShowChassisSCB {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowChassisSCB: $_" if ($debug);

    s/^[a-z]+@//;
    ProcessHistory("","","","# $_");
    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^system (shutdown message from|going down )/i);
	next if (/^\{(master|backup|linecard|primary|secondary)(:(node)?\d+)?\}/);

	return(0) if ($junos::ShowChassisSCB);
	/error: the chassis(-control)? subsystem is not r/ && return(-1);
	/Couldn\'t initiate connection/ && return(-1);
	/Unrecognized command/ && return(1);
	/command is not valid/ && return(1);
	/^\s+\^/ && return(1);
	/syntax error/ && return(1);

	/ Temperature/ && next;
	/ temperature/ && next;
	/ utilization/ && next;
	/ Start time/ && next;
	/ Uptime/ && next;
	/ (IP|MLPS) routes:/ && next;
	/ used:/ && next;
	ProcessHistory("","","","# $_");
    }
    $ShowChassisSCB = 1;
    return(0);
}

# This routine parses "show chassis alarms"
sub ShowChassisAlarms {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowChassisAlarms: $_" if ($debug);

    s/^[a-z]+@//;
    ProcessHistory("","","","# $_");
    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^system (shutdown message from|going down )/i);
	next if (/^\{(master|backup|linecard|primary|secondary)(:(node)?\d+)?\}/);

	/Unrecognized command/ && return(1);
	/command is not valid/ && return(1);
	/^\s+\^/ && return(1);
	/syntax error/ && return(1);

	ProcessHistory("","","","# $_");
    }
    return(0);
}

# This routine parses "show system autoinstallation status"
sub ShowSystemAutoinstall {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowSystemAutoinstall: $_" if ($debug);

    s/^[a-z]+@//;
    ProcessHistory("","","","# $_");
    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^system (shutdown message from|going down )/i);
	next if (/^\{(master|backup|linecard|primary|secondary)(:(node)?\d+)?\}/);

	/Unrecognized command/ && return(1);
	/command is not valid/ && return(1);
	/^\s+\^/ && return(1);
	/syntax error/ && return(1);

	ProcessHistory("","","","# $_");
    }
    return(0);
}

# This routine parses "show system configuration database usage"
# XXX this does not work with older JunOS because the unrecognized command
#     is mangled by the cli parser and then does not match what was sent!
#     so, this is a stand-alone function for now.
sub ShowSystemConfDB {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowSystemConfDB: $_" if ($debug);

    s/^[a-z]+@//;
    ProcessHistory("","","","# $_");
    while (<$INPUT>) {
	tr/\015//d;
	($found_end = 1, last) if (/^$prompt/);
	next if (/^system (shutdown message from|going down )/i);
	next if (/^\{(master|backup|linecard|primary|secondary)(:(node)?\d+)?\}/);

	/Unrecognized command/ && return(0);
	/command is not valid/ && return(0);
	/^\s+\^/ && return(0);
	/syntax error/ && return(0);

	# trim fractional part of the sizes to reduce churn
	s/\.\d+ ([GKM]B)/ $1/;

	ProcessHistory("","","","# $_");
    }
    return(0);
}


sub ShowSystemCoreDumps {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowSystemCoreDumps: $_" if ($debug);

    s/^[a-z]+@//;
    ProcessHistory("","","","# $_");
    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^\{(master|backup|linecard|primary|secondary)(:(node)?\d+)?\}/);

	/Unrecognized command/ && return(1);
	/command is not valid/ && return(1);
	/^\s+\^/ && return(1);
	/syntax error/ && return(1);
	/^JUNOS / && <$INPUT> && next;
	/No such file or directory$/ && next;

	ProcessHistory("","","","# $_");
    }
    return(0);
}

# This routine parses "show system license"
sub ShowSystemLicense {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowSystemLicense: $_" if ($debug);

    s/^[a-z]+@//;
    ProcessHistory("","","","# $_");
    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^system (shutdown message from|going down )/i);
	next if (/^\{(master|backup|linecard|primary|secondary)(:(node)?\d+)?\}/);
	return -1 if (/error: select: protocol failure /i);
	return -1 if (/error: abnormal communication /i);

	# licenses used changes constantly.  distill it to a percentage.
	# example input:
	# License usage:
	#                                  Licenses     Licenses    Licenses    Expiry
	#   Feature name                       used    installed      needed
	#   dynamic-vpn                           1            2           0    permanent
	if (/^(\s+(?:VMX|dynamic|mobile|scale|service|scale-subscriber|subscriber)-\S+)(\s+)(\d+)(\s+\d+)(.*$)/) {
	    my($a, $sp, $used, $avail, $rem) = ($1, $2, $3, $4, $5);
	    my($spl, $usedl) = (length($sp), length($used));
	    my($pcnt, $usage, $usagel);
	    if ($avail < 1) {
		$pcnt = ">100";
		$usage = ">0";
	    } else {
		if ($filter_osc >= 2) {
		    $usage = "--";
		} elsif ($avail < 100) {
		    # if license count is small, percentage doesn't do much to
		    # stabilize the output - just skip it.
		    $usage = "--";
		} else {
		    $pcnt = int(($used + 0.0) / ($avail + 0.0) * 100);
		    $usage = sprintf("%s%%", $pcnt);
		}
	    }
	    $usagel = length($usage) ;
	    $spl = $spl + $usedl - $usagel;

	    my($fmt) = "%s%-" . $spl . "s%s%s%s\n";
	    $_ = sprintf($fmt, $a, "", $usage, $avail, $rem);
	}

	/Unrecognized command/ && return(1);
	/command is not valid/ && return(1);
	/^\s+\^/ && return(1);
	/syntax error/ && return(1);

	ProcessHistory("","","","# $_");
    }
    return(0);
}

# This routine parses "show system license keys"
sub ShowSystemLicenseKeys {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowSystemLicenseKeys: $_" if ($debug);

    s/^[a-z]+@//;
    ProcessHistory("","","","# $_");
    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^system (shutdown message from|going down )/i);
	next if (/^\{(master|backup|linecard|primary|secondary)(:(node)?\d+)?\}/);

	/Unrecognized command/ && return(1);
	/command is not valid/ && return(1);
	/^\s+\^/ && return(1);
	/syntax error/ && return(1);

	ProcessHistory("","","","# $_");
    }
    return(0);
}

# This routine parses "show system boot-messages"
sub ShowSystemBootMessages {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowSystemBootMessages: $_" if ($debug);

    s/^[a-z]+@//;
    ProcessHistory("","","","# $_");
    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^system (shutdown message from|going down )/i);
	next if (/^\{(master|backup|linecard|primary|secondary)(:(node)?\d+)?\}/);

	/Unrecognized command/ && return(1);
	/command is not valid/ && return(1);
	/^\s+\^/ && return(1);
	/syntax error/ && return(1);

	/^JUNOS / && <$INPUT> && next;
	/^Timecounter "TSC" / && next;
	/^real memory / && next;
	/^avail memory / && next;
	/^\/dev\// && next;
	ProcessHistory("","","","# $_");
    }
    return(0);
}

# This routine parses "show version"
sub ShowVersion {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowVersion: $_" if ($debug);

    s/^[a-z]+@//;
    ProcessHistory("","","","# $_");
    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	return -1 if (/select: protocol failure /i);	# fail sending cmd
	next if (/^\s*$/);
	next if (/^system (shutdown message from|going down )/i);
	next if (/^\{(master|backup|linecard|primary|secondary)(:(node)?\d+)?\}/);
	/error: abnormal communication termination with / && return(-1);
	/error: could not connect to \S+ : no route to host/i && return(-1);

	/warning: .* subsystem not running - not needed by configuration/ && next;

	/^Juniper Networks is:/ && ProcessHistory("","","","# \n# $_") && next;
	ProcessHistory("","","","# $_");
    }
    ProcessHistory("","","","#\n");

    return(0);
}

# This routine parses "show configuration"
sub ShowConfiguration {
    my($INPUT, $OUTPUT, $cmd) = @_;
    my($lines) = 0;
    my($snmp) = 0;
    print STDERR "    In ShowConfiguration: $_" if ($debug);

    s/^[a-z]+@//;
    ProcessHistory("","","","# $_");
    while (<$INPUT>) {
	tr/\015//d;
	next if (/^\s*$/);
	# end of config - hopefully.  juniper does not have a reliable
	# end-of-config tag.  appears to end with "\nPROMPT>", but not sure.
	if (/^$prompt/) {
	    $found_end++;
	    last;
	}
	next if (/^system (shutdown message from|going down )/i);
	next if (/^## last commit: /i);
	next if (/^\{(master|backup|linecard|primary|secondary)(:(node)?\d+)?\}/);
	$lines++;

	/^database header mismatch: / && return(-1);
	/^version .*;\d+$/ && return(-1);

	s/ # SECRET-DATA$//;
	s/ ## SECRET-DATA$//;
	# filter snmp community, when in snmp { stanza }
	/^snmp/ && $snmp++;
	/^}/ && ($snmp = 0);
	if ($snmp && /^(\s*)(community|trap-group) [^ ;]+(\s?[;{])$/) {
		if ($filter_commstr) {
		    $_ = "$1$2 \"<removed>\"$3\n";
		}
	}
	if (/(\s*authentication-key )[^ ;]+/ && $filter_pwds >= 1) {
	    ProcessHistory("","","","#$1<removed>$'");
	    next;
	}
	if (/(\s*md5 \d+ key )[^ ;]+/ && $filter_pwds >= 1) {
	    ProcessHistory("","","","#$1<removed>$'");
	    next;
	}
	if (/(\s*hello-authentication-key )[^ ;]+/ && $filter_pwds >= 1) {
	    ProcessHistory("","","","#$1<removed>$'");
	    next;
	}
	# don't filter this one - there is no secret here.
	if (/^\s*permissions .* secret /) {
	    ProcessHistory("","","","$_");
	    next;
	}
	if (/^(.*\s(secret|simple-password) )[^ ;]+/ && $filter_pwds >= 1) {
	    ProcessHistory("","","","#$1<removed>$'");
	    next;
	}
	if (/(\s+encrypted-password )[^ ;]+/ && $filter_pwds >= 2) {
	    ProcessHistory("","","","#$1<removed>$'");
	    next;
	}
	if (/(\s+ssh-(rsa|dsa) )\"/ && $filter_pwds >= 2) {
	    ProcessHistory("","","","#$1<removed>;\n");
	    next;
	}
	if (/^(\s+(pre-shared-|)key (ascii-text|hexadecimal) )[^ ;]+/ && $filter_pwds >= 1) {
	    ProcessHistory("","","","#$1<removed>$'");
	    next;
	}
	ProcessHistory("","","","$_");
    }

    if ($lines < 3) {
	printf(STDERR "ERROR: $host configuration appears truncated.\n");
	$found_end = 0;
	return(-1);
    }

    return(0);
}

1;
