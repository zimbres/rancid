package sros;
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
#  sros.pm - Nokia (Alcatel-Lucent) SR OS rancid procedures

use 5.010;
use strict 'vars';
use warnings;
no warnings 'uninitialized';
require(Exporter);
our @ISA = qw(Exporter);

use rancid 3.12;

our $proc;
our $memoryseen;

@ISA = qw(Exporter rancid main);
#XXX @Exporter::EXPORT = qw($VERSION @commandtable %commands @commands);

# load-time initialization
sub import {
    0;
}

# post-open(collection file) initialization
sub init {
    $proc = "";
    $memoryseen = 0;

    # add content lines and separators
    ProcessHistory("","","","#RANCID-CONTENT-TYPE: $devtype\n");
    ProcessHistory("COMMENTS","keysort","A0","#\n");	# memory summary
    ProcessHistory("COMMENTS","keysort","B0","#\n");	# chassis summary
    ProcessHistory("COMMENTS","keysort","C0","#\n");	# show information
    ProcessHistory("COMMENTS","keysort","D0","#\n");    # show redundancy
    ProcessHistory("COMMENTS","keysort","E0","#\n");	# show chassis

    0;
}

# main loop of input of device output
sub inloop {
    my($INPUT, $OUTPUT) = @_;
    my($cmd, $rval);

TOP: while(<$INPUT>) {
	tr/\015//d;
CMD:	if (/[#]\s?logout\s*$/) {
	    $clean_run = 1;
	    last;
	}
	if (/^Error:/ &&
	    !(/^Error: Invalid parameter\./ || /^Error: Bad command\./)) {
	    print STDOUT ("$host clogin error: $_");
	    print STDERR ("$host clogin error: $_") if ($debug);
	    $clean_run = 0;
	    last;
	}
	while (/[#]\s*($cmds_regexp)\s*$/) {
	    $cmd = $1;
	    if (!defined($prompt)) {
		$prompt = ($_ =~ /^[*]?([^#>]+[#])/)[0];
		$prompt =~ s/([][}{)(+*\\])/\\$1/g;
		$prompt = "[*]?$prompt";
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
	    # filter the modified-config indicator ("*") from the line.
	    /^$prompt/ && s/^[*]//;
	    $rval = &{$commands{$cmd}}($INPUT, $OUTPUT, $cmd);
	    delete($commands{$cmd});
	    if ($rval == -1) {
		$clean_run = 0;
		last TOP;
	    }
	    if (defined($prompt)) {
		if (/$prompt/) {
		    goto CMD;
		}
	    }
	}
    }
}

# This routine parses "file type bootlog.txt"
sub BootLog {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In BootLog: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^$/);
	return(-1) if (/error: invalid parameter/i);
	return(-1) if (/minor: cli command not allowed for this user/i);
        # if file doesn't exist, return 0
        return(0) if (/minor: cli could not access file/i);

	if (/total memory:\s+(\S+)\s+chassis type:\s+(\S+)\s+card type:\s+(\S+)/i) {
	    next if ($memoryseen++);
	    ProcessHistory("COMMENTS","keysort","A1",
			   "#Total memory: $1\n");
	    ProcessHistory("COMMENTS","keysort","B1",
			   "#Chassis type: $2\n");
	    ProcessHistory("COMMENTS","keysort","B2",
			   "#Card type: $3\n");
	}
	/^chassis serial number is \'(.*)\'/i &&
	    ProcessHistory("COMMENTS","keysort","B1",
			   "#Chassis serial number: $1\n") && next;
    }
}
# This routine parses "show bof"
sub ShowBOF {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowBOF: $_" if ($debug);
    ProcessHistory("BOF","","","#\n# $_");

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^$/);
	return(-1) if (/error: invalid parameter/i);
	return(-1) if (/minor: cli command not allowed for this user/i);
	# context lines
	/^\[]$/i && next;
	/^INFO: CLI #\d+: Switching to the .* engine/ && next;
	/show bof/i && next;

	/[-=]+$/i && next;
	ProcessHistory("BOF","","","# $_");
    }
}
# This routine parses "show card detail"
sub ShowCardDetail {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowCardDetail: $_" if ($debug);
    ProcessHistory("COMMENTS","keysort","E6","#\n# $_");

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^$/);
	return(-1) if (/error: invalid parameter/i);
	return(-1) if (/minor: cli command not allowed for this user/i);
	# context lines
	/^\[]$/i && next;

	# humanize free space
	if (/^(\s+free space\s+:\s+)([0-9,]+\s+.*)/i) {
	    my($preamble) = $1;
	    my($space) = bytes2human(human2bytes($2));

	    ProcessHistory("COMMENTS","keysort","E6","# $preamble$space\n");
	    next;
	}

	# temp varies in "show card detail"
	next if (/^(\s+Temperature\s+:)\s+\d+C/);
	next if (/^(Config file|BOF) last (saved|modified)\s+:/ && ($filter_osc >= 2));

	# power data
	if (/hardware resources .power-zone/i) {
	    while (<$INPUT>) {
		tr/\015//d;
		last TOP if (/^$prompt/);
		last if (/(^\s*$|^=+)/);
	    }
	}

	/[-=]+$/i && next;

	ProcessHistory("COMMENTS","keysort","E6","# $_");
    }
}
# This routine parses "show card state"
sub ShowCardState {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowCardState: $_" if ($debug);
    ProcessHistory("COMMENTS","keysort","E5","#\n# $_");

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^$/);
	return(-1) if (/error: invalid parameter/i);
	return(-1) if (/minor: cli command not allowed for this user/i);
	# context lines
	/^\[]$/i && next;

	/[-=]+$/i && next;
	ProcessHistory("COMMENTS","keysort","E5","# $_");
    }
}
# This routine parses "show chassis"
sub ShowChassis {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowChassis: $_" if ($debug);
    ProcessHistory("COMMENTS","keysort","E1","# $_");

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*$cmd\s*)$/);
	next if (/^\s+\^$/);
	return(-1) if (/error: invalid parameter/i);
	return(-1) if (/minor: cli command not allowed for this user/i);
	# context lines
	/^\[]$/i && next;
	/^$/i && next; # extra blank lines tr doesn't remove

	/[-=]+$/i && next;

	/^\s+type\s+:\s+(.*)/i &&
	    ProcessHistory("COMMENTS","keysort","E1","# $_") &&
	    next;
	/^\s+serial number\s+:\s+(.*)/i &&
	    ProcessHistory("COMMENTS","keysort","B1",
			   "#Chassis serial number: $1\n") &&
	    ProcessHistory("COMMENTS","keysort","E1","# $_") &&
	    next;
	ProcessHistory("COMMENTS","keysort","E1","# $_");
    }
}
# This routine parses "show chassis environment"
sub ShowChassisEnv {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowChassisEnv: $_" if ($debug);
    ProcessHistory("COMMENTS","keysort","E2","#\n# $_");

TOP: while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^$/);
	return(-1) if (/error: invalid parameter/i);
	return(-1) if (/minor: cli command not allowed for this user/i);
	# context lines
	/^\[]$/i && next;

	# power data
	if (/hardware resources .power-zone/i) {
	    while (<$INPUT>) {
		tr/\015//d;
		last TOP if (/^$prompt/);
		last if (/(^\s*$|^=+)/);
	    }
	}

	/speed/i && next;

	/[-=]+$/i && next;
	ProcessHistory("COMMENTS","keysort","E2","# $_");
    }
}
# This routine parses "show chassis power-supply"
sub ShowChassisPS {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowChassisPS: $_" if ($debug);
    ProcessHistory("COMMENTS","keysort","E3","#\n# $_");

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^$/);
	return(0) if (/error: invalid parameter/i);	# cmd for 7750 SR only
	/\^+/i && next;
	return(0) if (/minor: .* unknown element/i);    # cmd for 7750 SR only
	return(-1) if (/minor: cli command not allowed for this user/i);
	# context lines
	/^\[]$/i && next;

	/[-=]+$/i && next;
	ProcessHistory("COMMENTS","keysort","E3","# $_");
    }
}
# This routine parses "show chassis power-management"
sub ShowChassisPM {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowChassisPM: $_" if ($debug);
    ProcessHistory("COMMENTS","keysort","E4","#\n# $_");

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^$/);
	return(0) if (/error: invalid parameter/i);	# cmd for 7950 XRS only
	/\^+/i && next;
	return(0) if (/minor: .* unknown element/i);    # cmd for 7950 XRS only
	return(-1) if (/minor: cli command not allowed for this user/i);
        # context lines
        /^\[]$/i && next;

	/volts/i && next;
	/watts/i && next;
	/amps/i && next;
	/[-=]+$/i && next;
	ProcessHistory("COMMENTS","keysort","E4","# $_");
    }
}
# This routine parses "show debug"
sub ShowDebug {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowDebug: $_" if ($debug);
    ProcessHistory("","","","#\n# $_");

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^$/);
	return(-1) if (/error: invalid parameter/i);
	return(-1) if (/minor: cli command not allowed for this user/i);
	# context lines
	/^\[]$/i && next;
	/^INFO: CLI #\d+: Switching to the .* engine/ && next;
	/show debug/i && next;

	ProcessHistory("","","","$_");
    }
}
# This routine parses "show redundancy synchronization"
sub ShowRedundancy {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowRedundancy: $_" if ($debug);
    ProcessHistory("COMMENTS","keysort","D2","# $_");

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^$/);
        # not on 7210 SAS, return 0
	return(0) if (/error: invalid parameter/i);
	return(0) if (/minor: .* synchronization is only supported/i);
	return(-1) if (/minor: cli command not allowed for this user/i);
	# context lines
	/^\[]$/i && next;

	/[-=]+$/i && next;
	/standby up time/i && next;
	/last config file sync time/i && next;
	/last boot env sync time/i && next;
	/last rollback sync time/i && next;
	/last cert sync time/i && next;

	ProcessHistory("COMMENTS","keysort","D2","# $_");
    }
}
# This routine parses "show system information"
sub ShowSystemInfo {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowSystemInfo: $_" if ($debug);
    $_ =~ s/ +/ /;
    ProcessHistory("COMMENTS","keysort","C1","# $_");

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^$/);
	return(-1) if (/error: invalid parameter/i);
	return(-1) if (/minor: cli command not allowed for this user/i);
	# context lines
	/^\[]$/i && next;

	/[-=]+$/i && next;
	/system up time/i && next;
	# User Last Modified     : someuname
	# Time Last Modified     : 2018/05/29 09:15:32
	/(user|time) last modified/i && ($filter_osc >= 2) && next;
	# Changes Since Last Save: Yes
	/changes since last save/i && ($filter_osc >= 2) && next;
	/time last saved/i && ($filter_osc >= 2) && next;


	if (/system type\s+:\s+(.*)/i) {
	    $proc = $1;
	    ProcessHistory("COMMENTS","keysort","B4",
			   "#System type: $proc\n");
	}
	if (/system version\s+:\s+(.*)/i) {
	    $proc = $1;
	    ProcessHistory("COMMENTS","keysort","B5",
			   "#System version: $proc\n");
	}
	ProcessHistory("COMMENTS","keysort","C1","# $_");
    }
}
# This routine parses "admin display-config index"
sub WriteTermIndex {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In WriteTermIndex: $_" if ($debug);
    ProcessHistory("","","","#\n# $_");

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^$/);
	return(-1) if (/error: invalid parameter/i);
	return(-1) if (/minor: cli command not allowed for this user/i);

	/# (timos-|all rights reserved|built on)/i && next;
	/# Generated /i && next;

	/^#-+$/i && next;
	s/echo \"(.*)\"/# $1/i;

	next if (/^# finished \S{3} \S{3} /i);
	ProcessHistory("","","","$_");
    }
}
# This routine parses "admin display-config"
sub WriteTerm {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In WriteTerm: $_" if ($debug);
    ProcessHistory("","","","#\n# $_");

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^$/);
	return(-1) if (/error: invalid parameter/i);
	return(-1) if (/minor: cli command not allowed for this user/i);

	/# (timos-|all rights reserved|built on)/i && next;
	/# Generated /i && next;

	/^#-+$/i && next;
	s/echo \"(.*)\"/# $1/i;

	# password/community filtering
	if (/^(\s+community) "[^"]*" /) {
	    if ($filter_commstr) {
		ProcessHistory("SNMPSERVERCOMM","keysort","$_",
			       "#$1 <removed> $'") && next;
	    } else {
		ProcessHistory("SNMPSERVERCOMM","keysort","$_","$_") && next;
	    }
	}
	if (/^(\s+trap-target\s+.*)\s+(notify-community)\s+("\S+")/) {
	    if ($filter_commstr) {
		ProcessHistory("","","","#$1 $2 <removed>$'") && next;
	    } else {
		ProcessHistory("","","","$_") && next;
	    }
	}
	if (/^(\s+password)\s+("\$\S+")/) {
	    if ($filter_pwds >= 2) {
		ProcessHistory("","","","#$1 <removed>$'") && next;
	    } else {
		ProcessHistory("","","","$_") && next;
	    }
	}

	# end of config.
	if (/^# finished \S{3} \S{3} /i) {
	    $found_end = 1;
	    return(0);
	}
	ProcessHistory("","","","$_");
    }

    return(0);
}

# This routine parses "admin show configuration" in the MD-CLI
sub WriteTermMD {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In WriteTermMD: $_" if ($debug);
    ProcessHistory("","","","#\n# $_");

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	next if (/^\s+\^$/);
	return(-1) if (/error: invalid parameter/i);
	return(-1) if (/minor: cli command not allowed for this user/i);
	# context lines
	/^\[]$/i && next;

	/# (timos-|all rights reserved|built on)/i && next;
	/# Generated /i && next;

	/^#-+$/i && next;
	s/echo \"(.*)\"/# $1/i;

	# password/community filtering
	if (/^(\s+community) "[^"]*" /) {
	    if ($filter_commstr) {
		ProcessHistory("SNMPSERVERCOMM","","", "#$1 <removed> $'") &&
		next;
	    } else {
		ProcessHistory("SNMPSERVERCOMM","","","$_") && next;
	    }
	}
	if (/^(\s+trap-target\s+.*)\s+(notify-community)\s+("\S+")/) {
	    if ($filter_commstr) {
		ProcessHistory("","","","#$1 $2 <removed>$'") && next;
	    } else {
		ProcessHistory("","","","$_") && next;
	    }
	}
	if (/^(\s+password)\s+("\$\S+")/) {
	    if ($filter_pwds >= 2) {
		ProcessHistory("","","","#$1 <removed>$'") && next;
	    } else {
		ProcessHistory("","","","$_") && next;
	    }
	}

	# end of config.
	if (/^# finished \S{3} \S{3} /i) {
	    $found_end = 1;
	    return(0);
	}
	ProcessHistory("","","","$_");
    }

    return(0);
}

1;
