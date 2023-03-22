package arbor;
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
#  arbor.pm - Arbor Networks appliances rancid procedures

use 5.010;
use strict 'vars';
use warnings;
require(Exporter);
our @ISA = qw(Exporter);

use rancid 3.12;

@ISA = qw(Exporter rancid main);
#XXX @Exporter::EXPORT = qw($VERSION @commandtable %commands @commands);

# load-time initialization
sub import {
    # force a terminal type so as not to confuse the POS with "network".
    # Seems that it might also support "dumb".
    $ENV{'TERM'} = "vt100";

    $timeo = 240;			# anlogin timeout in seconds

    0;
}

# post-open(collection file) initialization
sub init {
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
	if ( (/\>\s?logout$/) || $found_end ) {
	    $clean_run=1;
	    last;
	}
	if (/^Error:/) {
	    print STDOUT ("$host anlogin error: $_");
	    print STDERR ("$host anlogin error: $_") if ($debug);
	    $clean_run = 0;
	    last;
	}
	while (/[#>]\s*($cmds_regexp)\s*$/) {
	    $cmd = $1;
	    if (!defined($prompt)) {
		$prompt = ($_ =~ /^([^#>]+[#>])/)[0];
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

# This routine parses "config show"
sub ShowConfig {
    my($INPUT, $OUTPUT, $cmd) = @_;
    my($linecnt) = 0;
    print STDERR "    In ShowConfig: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	return(1) if (/invalid command/i);

	# some stupid timer error from this half-assed device
	next if (/comsh: timer error, idle timeout will be unavailable/i);

	# sort mgmt ACLs
	if (/ip access add (\S+) all (\S+)/) {
	    ProcessHistory("IPACCESS_$1","$aclsort","$2","$_"); next;
	}

	# sort IP addresses in policy and display one-per-line as comments so
	# that they are readable and it is easier to see what changed in the
	# policy. There does not appear to be a way to split these lines and
	# have the saved config still be loadable into the device.
	if (/(services sp managed_objects edit \"[^"]*\" match set cidr_blocks) (.*)/ ||
	    /(services sp managed_objects edit \"[^"]*\" match set cidr_v6_blocks) (.*)/ ||
	    /(services sp managed_objects edit \"[^"]*\" tags add \"[^"]*\") (.*)/ ||
	    /(services sp managed_objects edit \"[^"]*\" portal mitigation tms scope set) (.*)/) {
	    ProcessHistory("MG_OBJ","","","$_");
	    my(@ips) = split(/,/, $2);
	    next if ($#ips < 2);
	    ProcessHistory("MG_OBJ","","","# $1 \\\n");
	    my($ip, $n) = (0,0);
	    foreach $ip (@ips) {
		$n++;
		if ($n <= $#ips) {
		    ProcessHistory("MG_OBJ","$aclsort","$ip","#\t\t\t\t$ip,\\\n");
		} else {
		    ProcessHistory("MG_OBJ","$aclsort","$ip","#\t\t\t\t$ip\n");
		}
	    }
	    next;
	}

	if (/(services sp device edit .+ snmp community set )\S+/) {
	    if ($filter_commstr) {
		ProcessHistory("","","","# $1 <removed>$'"); next;
	    }
	}

	if (/^(services sp router edit \S+ bgp md5_secret set )\S+/
	    && $filter_pwds >= 1) {
	    ProcessHistory("","","","# $1<removed>$'");
	    next;
	}

	if (/^(services sp portal .+ edit .+ key set )\S+/
	    && $filter_pwds >= 1) {
	    ProcessHistory("","","","# $1<removed>$'");
	    next;
	}

	if (/^(services aaa tacacs server .* encrypted )\S+/
	    && $filter_pwds >= 1) {
	    ProcessHistory("","","","# $1<removed>$'");
	    next;
	}

	if (/^(services aaa local add .* encrypted )\S+/
	    && $filter_pwds >= 2) {
	    ProcessHistory("","","","# $1<removed>$'");
	    next;
	}

	ProcessHistory("","","","$_");
	$linecnt++;
    }

    # Arbor lacks a definitive "end of config" marker.
    if ($linecnt > 5) {
	$found_end = 1;
	return(1);
    }
    return(0);
}

# This routine parses "system hardware"
sub ShowHardware {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowHardware: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	return(1) if (/invalid command/i);

	# observed intermittently on T4008 running 8.2.0.
	return(-1) if (/error getting board version/i);

	# some stupid timer error from this half-assed device
	next if (/comsh: timer error, idle timeout will be unavailable/i);

	next if (/^boot time: /i);
	next if (/^load averages: /i);

	ProcessHistory("Inventory","","","# $_");
    }
    ProcessHistory("Inventory","","","#\n");
    return(0);
}

# This routine parses "show system version", "show system build-parameters"
sub ShowVersion {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowVersion: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	last if (/^$prompt/);
	next if (/^(\s*|\s*$cmd\s*)$/);
	return(1) if (/invalid command/i);

	# some stupid timer error from this half-assed device
	next if (/comsh: timer error, idle timeout will be unavailable/i);

	ProcessHistory("Version","","","# $_");
    }
    ProcessHistory("Version","","","#\n");
    return(0);
}

1;
