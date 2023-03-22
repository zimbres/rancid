package fortigate;
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
#  A library built on Stephen Gill's Netscreen stuff to accomodate
#  the Fortinet/Fortigate product line.  [d_pfleger@juniper.net]
#
#  fortigate.pm - Fortigate rancid procedures

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
	    print STDOUT ("$host fnlogin error: $_");
	    print STDERR ("$host fnlogin error: $_") if ($debug);
	    $clean_run = 0;
	    last;
	}
	while (/^.+[#\$]\s*($cmds_regexp)\s*$/) {
	    $cmd = $1;
	    # FortiGate prompts end with either '#' or '$'. Further, they may
	    # be prepended with a '~' if the hostname is too long. Therefore,
	    # we need to figure out what our prompt really is.
	    if (!defined($prompt)) {
		$prompt = ($_ =~ /^([^#\$]+~?[#\$])/)[0];
		$prompt =~ s/([][}{)(\\])/\\$1/g;
		# add the possible ~
		$prompt =~ s/~?([#\$])/~?\\$1/g;
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
	    $rval = &{$commands{$cmd}}($INPUT, $OUTPUT, $cmd);
	    delete($commands{$cmd});
	    if ($rval == -1) {
		$clean_run = 0;
		last TOP;
	    }
	}
	if (/[#\$]\s?exit$/) {
	    $clean_run = 1;
	    last;
	}
    }
}

# This routine parses "get system"
sub GetSystem {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In GetSystem: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	next if /^\s*$/;
	last if (/$prompt/);

	if ($filter_osc >= 2) {
	    next if (/^\s*APP-DB: .*/);
	    next if (/^\s*Botnet DB: .*/);
	    next if (/^\s*Extended DB: .*/);
	    next if (/^\s*industrial-db: .*/i);
	    next if (/^\s*IPS-DB: .*/);
	    next if (/^\s*IPS-ETDB: .*/);
	    next if (/^\s*IPS Malicious URL Database: .*/);
	    next if (/^\s*Virus-DB: .*/);
	}
	next if (/^system time:/i);
	next if (/^FortiClient application signature package:/);
	# Cluster uptime
	next if (/^\s*Cluster uptime:/);

	ProcessHistory("","","","#$_");
    }
    ProcessHistory("SYSTEM","","","\n");
    return(0);
}

sub GetFile {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In GetFile: $_" if ($debug);

    while (<$INPUT>) {
	last if (/$prompt/);
    }
    ProcessHistory("FILE","","","\n");
    return(0);
}

sub GetConf {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In GetConf: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	next if /^\s*$/;
	last if (/$prompt/);

	# System time is fortigate extraction time
	next if (/^\s*!System time:/);
	# remove occurrances of conf_file_ver
	next if (/^#?conf_file_ver=/);
	# filter last-login
	if (/^(\s*set)\slast-login\s(.*)/ && $filter_osc) {
	    ProcessHistory("","","","#$1 last-login <removed>\n");
	    next;
	}

	# filter cycling RSA private keys
	if ($filter_osc &&
	    /^\s*set private-key "-----BEGIN (RSA|ENCRYPTED) PRIVATE KEY-----/) {
	    ProcessHistory("","","","#$_");
	    ProcessHistory("","","","# <removed>\n");
	    while (<$INPUT>) {
		tr/\015//d;
		goto ENDGETCONF if (/$prompt/);

		if (/^\s*-----END (RSA|ENCRYPTED) PRIVATE KEY-----"/) {
	    	    ProcessHistory("","","","#$_");
		    last;
		}
	    }
	    next;
	}
	# filter ospf md5-keys
	if (/^(\s*set)\smd5-key\s(\d+)\s(.*)/ && $filter_osc) {
	    ProcessHistory("","","","#$1 md5-key $2 <removed>\n");
	    next;
	}
	# filter cycling password encryption
	if (/^(\s*set \S*( \d+)?)\s("?enc\s\S+"?)(.*)/i &&
	    ($filter_osc || $filter_pwds > 0)) {
	    ProcessHistory("ENC","","","#$1 ENC <removed> $4\n");
	    next;
	}

	ProcessHistory("","","","$_");
    }
ENDGETCONF:
    $found_end = 1;
    return(1);
}

1;
