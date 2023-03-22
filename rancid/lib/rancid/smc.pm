package smc;
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
#  smc.pm - SMC rancid procedures; and some Dell products.  started by
#  d_pfleger@juniper.net
#
# Code tested and working fine on these models:
#
#	DELL PowerConnect M8024 / M8024-k
#	DELL PowerConnect M6348
#	DELL PowerConnect N2048, N4032F and N4064.
#	DELL PowerConnect 62xx
#	DELL PowerConnect 7048
#	DELL 34xx (partially; configuration is incomplete)
#	DELL R1-2401
#
use 5.010;
use strict 'vars';
use warnings;
no warnings 'uninitialized';
require(Exporter);
our @ISA = qw(Exporter);

use rancid 3.12;

@ISA = qw(Exporter rancid main);
#XXX @Exporter::EXPORT = qw($VERSION @commandtable %commands @commands);

# load-time initialization
sub import {
    0;
}

# post-open(collection file) initialization
sub init {
    # add content lines and separators
    ProcessHistory("","","","!RANCID-CONTENT-TYPE: $devtype\n!\n");
    ProcessHistory("COMMENTS","keysort","A0","!\n");
    ProcessHistory("COMMENTS","keysort","B0","!\n");
    ProcessHistory("COMMENTS","keysort","C0","!\n");
    ProcessHistory("COMMENTS","keysort","D0","!\n");

    0;
}

# main loop of input of device output
sub inloop {
    my($INPUT, $OUTPUT) = @_;
    my($cmd, $rval);

TOP: while(<$INPUT>) {
	tr/\015//d;
	if (/^Error:/) {
	    print STDOUT ("$host hlogin error: $_");
	    print STDERR ("$host hlogin error: $_") if ($debug);
	    last;
	}
	while (/#\s*($cmds_regexp)\s*$/) {
	    $cmd = $1;
	    if (!defined($prompt)) {
		$prompt = ($_ =~ /^([^#]+#)/)[0];
		$prompt =~ s/([][}{)(\\])/\\$1/g;
		print STDERR ("PROMPT MATCH: $prompt\n") if ($debug);
	    }
	    print STDERR ("HIT COMMAND:$_") if ($debug);
	    if (!defined($commands{$cmd})) {
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
	    my($rval) = &{$commands{$cmd}}($INPUT, $OUTPUT, $cmd);
	    delete($commands{$cmd});
	    if ($rval == -1) {
		$clean_run = 0;
		last TOP;
	    }
	}
	if (/[>#]\s?logout(\s*connection.*closed.*)?$/i) {
	    $clean_run = 1;
	    last;
	}
    }
}

# This routine parses "dir"
sub Dir {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In Dir: $_" if ($debug);
    $_ =~ s/^[^#]*//;
    ProcessHistory("COMMENTS","keysort","D1","!\n! $_");

    while (<$INPUT>) {
	s/^\s+\015//g;
	tr/\015//d;
	next if /^\s*$/;
	last if(/$prompt/);
	# pager remnants like: ^H^H^H    ^H^H^H content
	s/[\b]+\s*[\b]*//g;

	# filter oscillating files
	next if /^aaafile\.prv/;

	ProcessHistory("COMMENTS","keysort","D1","! $_");
    }
    ProcessHistory("COMMENTS","keysort","D1","!\n");
    return(0);
}

sub ShowVer {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowVer: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	next if /^\s*$/;
	last if(/$prompt/);
	# pager remnants like: ^H^H^H    ^H^H^H content
	s/[\b]+\s*[\b]*//g;

	# Remove Uptime
	/ up time/i && next;

	ProcessHistory("COMMENTS","keysort","B1","! $_");
    }
    return(0);
}

sub ShowSys {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowSys: $_" if ($debug);
    $_ =~ s/^[^#]*//;
    ProcessHistory("COMMENTS","keysort","C1","!\n! $_");

    while (<$INPUT>) {
TOP:	s/^\s+\015//g;
	tr/\015//d;
	next if /^\s*$/;
	last if(/$prompt/);
	# pager remnants like: ^H^H^H    ^H^H^H content
	s/[\b]+\s*[\b]*//g;

	# Remove Uptime
	/ up time/i && next;

	# filter temperature sensor info form Dell N1148T-ON and Powerconnect
	# 7048 /Temperature Sensors:/; yet another format - a losing battle.
	if (/^(system thermal conditions|Temperature Sensors):/i) {
	    while (<$INPUT>) {
		s/^\s+\015//g;
		tr/\015//d;
		goto ENDSHOWSYS if (/$prompt/);
		# next section header
		goto TOP if (/^(\w\s*)+:/);
	    }
	} elsif (/Temperature \(Celsius\)/) {
	    # filter temperature sensor info for Dell 6428 stacks
	    ProcessHistory("COMMENTS","keysort","C1","! $_");
	    ProcessHistory("COMMENTS","keysort","C1","! Unit\tStatus\n");
	    ProcessHistory("COMMENTS","keysort","C1","! ----\t------\n");
	    while (<$INPUT>) {
		s/^\s+\015//g;
		tr/\015//d;
		goto ENDSHOWSYS if (/$prompt/);
		/(\d+)\s+\d+\s+(.*)$/ &&
		ProcessHistory("COMMENTS","keysort","C1","! $1\t$2\n");
		/^\s*$/ && last;
	    }
	} elsif (/Temperature/) {
	    # Filter temperature sensor info for Dell M6348 and M8024 blade
	    # switches.
	    #
	    # M6348 and M8024 sample lines:
	    #   Unit     Description       Temperature    Status
	    #                               (Celsius)
	    #   ----     -----------       -----------    ------
	    #   1        System            39             Good
	    #   2        System            39             Good
	    ProcessHistory("COMMENTS","keysort","C1",
			   "! Unit\tDescription\tStatus\n");
	    ProcessHistory("COMMENTS","keysort","C1",
			   "! ----\t-----------\t------\n");
	    while (<$INPUT>) {
		/\(celsius\)/i && next;
		s/^\s+\015//g;
		tr/\015//d;
		goto ENDSHOWSYS if (/$prompt/);
		/(\d+)\s+(\w+)\s+\d+\s+(.*)$/ &&
		ProcessHistory("COMMENTS","keysort","C1","! $1\t$2\t\t$3\n");
		/^\s*$/ && last;
	    }
	}

	# filter power rates and timestamps from 7024 power supply info
	# Power Supplies:
	#  
	# Unit  Description    Status     Average     Current          Since
	#                                  Power       Power         Date/Time
	#                                 (Watts)     (Watts)
	# ----  -----------  -----------  ----------  --------  -------------------
	# 1     System       OK            1.4        65.2
	# 1     Internal     OK           N/A         N/A       10/05/2017 20:18:35
	if (/power supplies/i) {
	    ProcessHistory("COMMENTS","keysort","C1", "!\n");
	    ProcessHistory("COMMENTS","keysort","C1",
		"! Unit\tDescription\tStatus\n");
	    ProcessHistory("COMMENTS","keysort","C1",
		"! ----\t-----------\t------\n");
	    while (<$INPUT>) {
		s/^\s+\015//g;
		tr/\015//d;
		goto ENDSHOWSYS if(/$prompt/);
		/^(unit\s|--+\s|\s)/i && next;
		if (/(\d+)\s+(\w+)\s+(\w+(\s\w+)?)\s/) {
		    if (length($2) >= 8) {
			ProcessHistory("COMMENTS","keysort","C1","! $1\t$2\t$3\n");
		    } else {
			ProcessHistory("COMMENTS","keysort","C1","! $1\t$2\t\t$3\n");
		    }
		}
		/^\s*$/ && last;
	    }
	}

	/system description: (.*)/i &&
	    ProcessHistory("COMMENTS","keysort","A1", "!Chassis type: $1\n") &&
	    next;

	ProcessHistory("COMMENTS","keysort","C1","! $_");
    }
ENDSHOWSYS:
    return(0);
}

sub ShowVlan {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowVlan: $_" if ($debug);
    $_ =~ s/^[^#]*//;
    ProcessHistory("COMMENTS","keysort","D1","!\n! $_");

    while (<$INPUT>) {
	s/^\s+\015//g;
	tr/\015//d;
	next if /^\s*$/;
	last if(/$prompt/);
	# pager remnants like: ^H^H^H    ^H^H^H content
	s/[\b]+\s*[\b]*//g;

	# Remove Uptime
	/ up time/i && next;
	ProcessHistory("COMMENTS","keysort","D1","! $_");
    }
    return(0);
}

# This routine processes a "write term" (aka show running-configuration)
sub WriteTerm {
    my($INPUT, $OUTPUT, $cmd) = @_;
    my($comment) = (0);
    print STDERR "    In WriteTerm: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	next if /^\s*$/;
	last if(/$prompt/);
	# pager remnants like: ^H^H^H    ^H^H^H content
	s/[\b]+\s*[\b]*//g;

	# skip consecutive comment lines
	if (/^!/) {
	    next if ($comment);
	    ProcessHistory("","","",$_);
	    $comment++;
	    next;
	}
	$comment = 0;

	/^building running-config/ && next;
	/^------+/ && ProcessHistory("","","","!$_") && next;
	/^router configuration/i && ProcessHistory("","","","!$_") && next;
	/^oob host config/i && ProcessHistory("","","","!$_") && next;
	/^empty configuration/i && ProcessHistory("","","","!$_") && next;

	if (/^username (\S+)(\s.*)? password ((\d) \S+|\S+)/) {
	    if ($filter_pwds >= 2) {
		ProcessHistory("USER","keysort","$1",
			       "!username $1$2 password <removed>\n");
	    } elsif ($filter_pwds >= 1 && $3 ne "5"){
		ProcessHistory("USER","keysort","$1",
			       "!username $1$2 password <removed>\n");
	    } else {
		ProcessHistory("USER","keysort","$1","$_");
	    }
	    next;
	}

	if (/^(enable password)( level \d+)? / && $filter_pwds >= 1) {
	    ProcessHistory("ENABLE","","","!$1$2 <removed>\n");
	    next;
	}

	if (/^password (\S+) encrypted/ && $filter_pwds > 1) {
	    ProcessHistory("","","","!password <removed> encrypted\n");
	    next;
	}
	if (/^password (\S+)$/ && $filter_pwds >= 1) {
	    ProcessHistory("","","","!password <removed>\n");
	    next;
	}

	if (/^(enable password level \d+) (\S+) encrypted/ && $filter_pwds > 1){
	    ProcessHistory("","","","!$1 <removed> encrypted\n");
	    next;
	}
	if (/^(enable password level \d+) (\S+)$/ && $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1 <removed> $'\n");
	    next;
	}

	# order/prune snmp-server host statements
	# we only prune lines of the form
	# snmp-server host a.b.c.d <community>
	if (/^(snmp-server host) (\d+\.\d+\.\d+\.\d+) (\S+)/) {
	    if ($filter_commstr) {
		ProcessHistory("SNMPSERVERHOST","ipsort",
			       "$2","!$1 $2 <removed>$'");
	    } else {
		ProcessHistory("SNMPSERVERHOST","ipsort","$2","$_");
	    }
	    next;
	}
	if (/^(snmp-server community) (\S+)/) {
	    if ($filter_commstr) {
		ProcessHistory("SNMPSERVERCOMM","keysort",
			       "$_","!$1 <removed>$'") && next;
	    } else {
		ProcessHistory("SNMPSERVERCOMM","keysort","$2","$_") && next;
	    }
	}

	# prune tacacs/radius server keys
	if (/^(tacacs-server|radius-server) key \w+/ && $filter_pwds >= 1) {
	    ProcessHistory("","","","!$1 <removed>$'"); next;
	}

	ProcessHistory("","","","$_");
    }
    $found_end = 1;
    return(1);
}

1;
