package rbt;
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
#  rbt.pm - Riverbed Steelhead

use 5.010;
use strict 'vars';
use warnings;
no warnings 'uninitialized';
require(Exporter);
our @ISA = qw(Exporter);

use rancid 3.12;

our $proc;
our $found_version;

our $type;				# device model, from ShowVersion

@ISA = qw(Exporter rancid main);
#XXX @Exporter::EXPORT = qw($VERSION @commandtable %commands @commands);

# load-time initialization
sub import {
    0;
}

# post-open(collection file) initialization
sub init {
    $found_version = 0;

    $type = undef;			# device model, from ShowVersion

    # add content lines and separators
    ProcessHistory("","","","#RANCID-CONTENT-TYPE: $devtype\n#\n");

    0;
}

# main loop of input of device output
sub inloop {
    my($INPUT, $OUTPUT) = @_;
    my($cmd, $rval);

TOP: while(<$INPUT>) {
	tr/\015//d;
	if (/^Error:/) {
	    print STDOUT ("$host clogin error: $_");
	    print STDERR ("$host clogin error: $_") if ($debug);
	    $clean_run = 0;
	    last;
	}
	while (/[>#]\s*($cmds_regexp)\s*$/) {
	    $cmd = $1;
	    if (!defined($prompt)) {
		$prompt = ($_ =~ /^([^#>]+[#>])/)[0];
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
	if (/[>#]\s?exit$/) {
	    $clean_run = 1;
	    last;
	}
    }
}

# This routine parses "show version"
sub ShowVersion {
    my($INPUT, $OUTPUT, $cmd) = @_;
    my($slave, $slaveslot);
    print STDERR "    In ShowVersion: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	if (/^$prompt/) { $found_version = 1; last};
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^$/);
	return(1) if (/Line has invalid autocommand /);
	return(1) if (/(invalid (input|command) detected|type help or )/i);
	return(0) if ($found_version);		# Only do this routine once
	return(-1) if (/command authorization failed/i);

	next if (/^uptime:/i);
	next if (/^cpu load averages:/i);

	if (/^product model:\s+(\S+)/i) {
	    $type = $1;
	    ProcessHistory("COMMENTS","keysort","A1", "#Chassis type: $1\n#\n");
	    next;
	}
	/^system memory:.*\/ (\S+ \S+) total/i &&
	    ProcessHistory("COMMENTS","keysort","B1", "# Memory: $1\n") &&
	    next;

	ProcessHistory("COMMENTS","keysort","X1", "# $_");
    }
    # flush the history
    ProcessHistory("","","", "#\n");
    return(0);
}

# This routine parses "show hardware all"
sub ShowHardware {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowHardware: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^$/);
	return(1) if (/Line has invalid autocommand /);
	return(1) if (/(invalid (input|command) detected|type help or )/i);

	ProcessHistory("COMMENTS","keysort","HW","# $_");
    }
    ProcessHistory("COMMENTS","keysort","HW","#\n");
    return(0);
}

# This routine parses "show Info"
sub ShowInfo {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowInfo: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^$/);
	return(1) if (/Line has invalid autocommand /);
	return(1) if (/(invalid (input|command) detected|type help or )/i);

	next if (/^(appliance|service) up ?time:/i);
	next if (/^temperature/i);
	next if (/^services needs a .*restart.* due to a config change/i);
	/^serial:\s+(\S+)/ &&
	    ProcessHistory("COMMENTS","keysort","B1", "#Serial Number: $1\n") &&
	    next;
    }
    ProcessHistory("COMMENTS","keysort","IO","#\n");
    return(0);
}

# This routine parses "show license"
sub ShowLicenses {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowLicenses: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^$/);
	return(1) if (/Line has invalid autocommand /);
	return(1) if (/(invalid (input|command) detected|type help or )/i);

	ProcessHistory("COMMENTS","keysort","LICENSE","#LICENSE: $_");
    }
    ProcessHistory("COMMENTS","keysort","LICENSE","#\n");
    return(0);
}

# This routine parses "show peers"
sub ShowPeers {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowPeers: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^$/);
	return(1) if (/Line has invalid autocommand /);
	return(1) if (/(invalid (input|command) detected|type help or )/i);

	ProcessHistory("COMMENTS","keysort","PEERS","#PEERS: $_");
    }
    ProcessHistory("COMMENTS","keysort","PEERS","#\n");
    return(0);
}

# This routine processes a "show configuration"
sub WriteTerm {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In WriteTerm: $_" if ($debug);
    my($comment, $linecnt) = (0,0);

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

	next if (/^\s*$/);
	$linecnt++;

	if (/^(\s*username \S+ password 7) \$6\$/) {
	    if ($filter_pwds >= 2) {
		ProcessHistory("USER","","","#$1 <removed>\n");
		next;
	    }
	} elsif (/^(\s*username \S+ password 7) / && $filter_pwds >= 1) {
	    ProcessHistory("USER","","","#$1 <removed>\n");
	    next;
	}

	if (/^(\s*service shared-secret secret (client|server)) \S+$/ ||
	    /^(\s*ip security shared secret) \S+$/) {
	    if ($filter_pwds >= 1) {
		ProcessHistory("USER","","","#$1 <removed>\n");
		next;
	    }
	}

	if (/^(\s+snmp-server community) (\S+)/) {
	    if ($filter_commstr) {
		ProcessHistory("SNMPSERVERCOMM","keysort","$_",
			       "#$1 <removed>$'") && next;
	    } else {
		ProcessHistory("SNMPSERVERCOMM","keysort","$_","$_") && next;
	    }
	}

	# catch anything that wasnt matched above.
	ProcessHistory("","","","$_");
    }

    # It lacks a definitive "end of config" marker.  If we have seen at least
    # 5 lines of config output, we can be reasonably sure that we received the
    # config.
    if ($linecnt > 5) {
	$found_end = 1;
	return(0);
    }

    return(0);
}

1;
