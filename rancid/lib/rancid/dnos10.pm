package dnos10;
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
#  dnos9.pm - Dell NOS10 rancid procedures - from Bjørn Skobba

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

$timeo = 90;				# clogin timeout in seconds

# main loop of input of device output
sub inloop {
    my($INPUT, $OUTPUT) = @_;
    my($cmd, $rval);

TOP: while(<$INPUT>) {
	tr/\015//d;
	if (/\#\s?exit$/) {
	    $clean_run=1;
	    last;
	}
	if (/^Error:/) {
	    print STDOUT ("$host hlogin error: $_");
	    print STDERR ("$host hlogin error: $_") if ($debug);
	    $clean_run=0;
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

# This routine parses "show version"
sub ShowVer {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowVer: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	next if (/^\s*$/);
	last if (/$prompt/);
	# pager remnants like: ^H^H^H    ^H^H^H content
	s/[\b]+\s*[\b]*//g;

	# Remove Uptime
	/^Up Time/ && next;

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
	s/^\s+\015//g;
	tr/\015//d;
REDO:	last if (/$prompt/);
	# pager remnants like: ^H^H^H    ^H^H^H content
	s/[\b]+\s*[\b]*//g;

	# Remove Uptime
	/^Up Time/i && next;

	if (/-- power supplies --/i) {
	    ProcessHistory("COMMENTS","keysort","C1","! $_");
	    # PSU-ID  Status      Type    AirFlow   Fan  Speed(rpm)  Status
	    # ----------------------------------------------------------------
	    # 1       up          AC      REVERSE   1    25800       up         
	    while (<$INPUT>) {
		s/^\s+\015//g;
		tr/\015//d;
		last if (/$prompt/);
		last if (/^-- /);		# next section
		/^\s*$/ && next;
		if (/^(\d+\s+\w+\s+\w+\s+\w+\s+\d+\s+)(\d+)(\s+\w+)\s*$/) {
		    my($sl) = length($2);
                    my($fmt) = "%s%-". $sl ."s%s\n";
                    $_ = sprintf($fmt, $1, "", $3);
		}
		ProcessHistory("COMMENTS","keysort","C1","! $_");
	    }
	    goto REDO;
	}
	if (/-- fan status --/i) {
	    ProcessHistory("COMMENTS","keysort","C1","! $_");
	    # FanTray  Status      AirFlow   Fan  Speed(rpm)  Status
	    # ----------------------------------------------------------------
	    # 1        up          REVERSE   1    11160       up         
	    while (<$INPUT>) {
		s/^\s+\015//g;
		tr/\015//d;
		last if (/$prompt/);
		last if (/^-- /);		# next section
		/^\s*$/ && next;
		if (/^(\d+\s+\w+\s+\w+\s+\d+\s+)(\d+)(\s+\w+)\s*$/) {
		    my($sl) = length($2);
                    my($fmt) = "%s%-". $sl ."s%s\n";
                    $_ = sprintf($fmt, $1, "", $3);
		}
		ProcessHistory("COMMENTS","keysort","C1","! $_");
	    }
	    goto REDO;
	}

	/current type\s*: (.*)/i &&
	    ProcessHistory("COMMENTS","keysort","A1", "!Chassis type: $1\n") &&
	    next;

	ProcessHistory("COMMENTS","keysort","C1","! $_");
    }
    return(0);
}

# This routine parses "show inventory"
sub ShowInventory {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowInventory: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	return(1) if /(Invalid input|Type help or )/;
	return(-1) if (/command authorization failed/i);

	/-----------------------------/ && next;
	ProcessHistory("COMMENTS","keysort","INVENTORY","!Inventory: $_");
    }
    ProcessHistory("COMMENTS","keysort","INVENTORY","!\n");
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
	next if (/^\s*$/);
	last if (/$prompt/);
	# pager remnants like: ^H^H^H    ^H^H^H content
	s/[\b]+\s*[\b]*//g;

	# Remove Uptime
	/^Up Time/i && next;
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
	next if (/^\s*$/);
	last if (/$prompt/);
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

	if (/^(username|system\-user) (\S+)(\s.*)? password ((\d) \S+|\S+)/) {
	    if ($filter_pwds >= 2) {
		ProcessHistory("USER","keysort","$1",
			       "!username $1 $2 password <removed>\n");
	    } elsif ($filter_pwds >= 1 && $3 ne "5"){
		ProcessHistory("USER","keysort","$1",
			       "!username $1 $2 password <removed>\n");
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
