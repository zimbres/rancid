package fss2;
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
#  onefinity.pm - Fujitsu FSS2/1finity rancid procedures
#

use 5.010;
use strict 'vars';
use warnings;
require(Exporter);
our @ISA = qw(Exporter);
$Exporter::Verbose=1;

use rancid 3.12;

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
    ProcessHistory("COMMENTS","keysort","A0","#\n");
    ProcessHistory("COMMENTS","keysort","B0","#\n");

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
	    $clean_run=0;
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
	    $clean_run=1;
	    last;
	}
    }
}

# This routine parses "show fw-info"
sub ShowFWinfo {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowFWinfo: $_" if ($debug);

    s/^[a-z]+@//;
    ProcessHistory("FWINFO","","","#\n# $_");
    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if /\[ok\]\[/i;

	ProcessHistory("FWINFO","","","# $_");
    }
    return(0);
}

# This routine parses "show inventory"
sub ShowInventory {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowInventory: $_" if ($debug);

    s/^[a-z]+@//;
    ProcessHistory("INVENTORY","","","#\n# $_");
    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if /\[ok\]\[/i;

	next if (/^inventory\s*$/i);

	ProcessHistory("INVENTORY","","","# $_");
    }
    return(0);
}

# This routine parses "show system"
sub ShowSystem {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowSystem: $_" if ($debug);

    s/^[a-z]+@//;
    ProcessHistory("COMMENTS","keysort","C","#\n# $_");
    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if /\[ok\]\[/i;

	next if /system (sys-)?uptime/i;
	/system neType\s+(.*)/ &&
	    ProcessHistory("COMMENTS","keysort","A1","#Chassis type: $1\n") &&
	    next;
	/system softwareVersion\s+(.*)/ &&
	    ProcessHistory("COMMENTS","keysort","B1","#Image: $1\n") && next;

	# drop cpu stats and process stats
	if (/^(index\s*user type\s*|\s*cpu\s*cpu\s*$)/i) {
	    while (<$INPUT>) {
		tr/\015//d;
		goto OUT if (/^$prompt/);	# should not occur
		goto OUT if /\[ok\]\[/i;

                last if (/^\s*$/);
	    }
	    next;
	}
 
	ProcessHistory("","","","# $_");
    }
OUT:
    return(0);
}

# This routine parses "show configuration"
sub WriteTerm {
    my($INPUT, $OUTPUT, $cmd) = @_;
    my($lines) = 0;
    my($snmp) = 0;
    print STDERR "    In WriteTerm: $_" if ($debug);

    s/^[a-z]+@//;
    ProcessHistory("COMMENTS","","","#\n# $_");
    while (<$INPUT>) {
	tr/\015//d;
	next if (/^\s*$/);

	# end of config - hopefully.  FSS2 does not have a reliable
	# end-of-config tag.  appears to end with "\nPROMPT>", but not sure.
	if (/^$prompt/ || /^\[ok\]\[/) {
	    $found_end++;
	    last;
	}
	next if (/^\s+(last-changed|last-updated|uptime)\s+/i);
	next if (/^\s+(replay-log-creation-time|replay-log-aged-time)\s+/i);
	next if (/^\s+sys-vstimer\s+/i);
	next if (/^\s+softwareversion\s+/i);
	next if (/^\s+(netype|vendor)\s+/i);
	$lines++;

	# filter snmp community, when in snmp { stanza }
	/^snmp/ && $snmp++;
	/^}/ && ($snmp = 0);
	if ($snmp && /^(\s*)(community|trap-group) [^ ;]+(\s?[;{])$/) {
		if ($filter_commstr) {
		    $_ = "$1$2 \"<removed>\"$3\n";
		}
	}
	# this is either cleartext or *; either way, it should be filtered.
	if (/(\s+password\s+)[^ ;]+/) {
	    ProcessHistory("","","","#$1<removed>$'");
	    next;
	}
	if (/(\s+crypt-password\s+)[^ ;]+/ && $filter_pwds >= 2) {
	    ProcessHistory("","","","#$1<removed>$'");
	    next;
	}
	ProcessHistory("","","","$_");
    }

    if ($lines < 3) {
	printf(STDERR "ERROR: $host configuration appears to be truncated.\n");
	$found_end = 0;
	return(-1);
    }

    return(0);
}

1;
