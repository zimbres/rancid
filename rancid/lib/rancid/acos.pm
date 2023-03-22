package acos;
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
# a10.pm - A10 rancid procedures

use 5.010;
use strict 'vars';
use warnings;
no warnings 'uninitialized';
require(Exporter);
our @ISA = qw(Exporter);

use rancid 3.12;

@ISA = qw(Exporter rancid main);

# load-time initialization
sub import {
    0;
}

# post-open(collection file) initialization
sub init {
    # add content lines and separators
    ProcessHistory("","","","!RANCID-CONTENT-TYPE: $devtype\n!\n");

    0;
}

# main loop of input of device output
sub inloop {
    my($INPUT, $OUTPUT) = @_;
    my($cmd, $rval);

TOP: while(<$INPUT>) {
	tr/\015//d;
CMD:	if (/[>#]\s?exit$/) {
	    $clean_run = 1;
	    last;
	}
	if (/^Error:/) {
	    print STDOUT ("$host a10login error: $_");
	    print STDERR ("$host a10login error: $_") if ($debug);
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

sub basicFilter {
    my($INPUT, $OUTPUT, $cmd, $prefix) = @_;

    while (<$INPUT>) {
	tr/\015//d;
	next if (/^\s*$/);
	next if (/^\s*\^$/);				# cli cmd error marker
	return(1) if (/% unrecognized command/i);	# cli cmd error
	return(1) if (/% incomplete command/i);		# cli cmd error
	last if (/$prompt/);

	s/\s*$/\n/;					# trim trailing WS
	ProcessHistory($prefix,"","","!$prefix: $_");
    }
    ProcessHistory($prefix,"","","!\n");
    return(0);
}

# parses show version
sub ShowVersion {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowVersion: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	next if /^\s*$/;
	last if (/$prompt/);

        next if (/Current time is/);
	next if (/The system has been up/);
        next if (/Last configuration saved/);
        next if (/Free Memory/);
	ProcessHistory("VERSION","","","!VERSION: $_");
    }
    ProcessHistory("VERSION","","","!\n");
    return(0);
}

# parses show admin
sub ShowAdmin {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowAdmin: $_" if ($debug);
    return basicFilter($INPUT, $OUTPUT, $cmd, "Users");
}

sub ShowAflex {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowAflex: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	next if /^\s*$/;
	last if (/^$prompt/);
	return(1) if (/% unrecognized command\./i);	# not in CGN/LSN image

	s/\s*$/\n/;					# trim trailing WS
        ProcessHistory("AFLEX", "", "", "!AFLEX: $_");
    }
    while (/show aflex (\S+) partition/) {
        my($name) = $1;
        my($found_content) = 0;

        ProcessHistory("AFLEX-$name", "", "", "aflex create $name\n");
        while (<$INPUT>) {
	    tr/\015//d;
	    last if (/^$prompt/);

            if ($found_content) {
		ProcessHistory("AFLEX-$name", "", "", "$_");
            } elsif (/^Content:/) {
                $found_content = 1
            }
        }
        if ($found_content) {
	    ProcessHistory("AFLEX-$name", "", "", ".\n");
        }
    }
    ProcessHistory("ADMIN","","","!\n");
    return(0);
}

# parses show bootimage
sub ShowBootimage {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowBootimage: $_" if ($debug);
    return basicFilter($INPUT, $OUTPUT, $cmd, "BootImage");
}

# parses show license
sub ShowLicense {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowLicense: $_" if ($debug);
    return basicFilter($INPUT, $OUTPUT, $cmd, "LICENSE");
}

# parses show running-config
sub ShowRunningConfig {
    my($INPUT, $OUTPUT, $cmd) = @_;
    my $comment = 0;
    print STDERR "    In ShowRunningConfig: $_" if ($debug);

    while (<$INPUT>) {
	tr/\015//d;
	next if (/^\s*$/);
	next if (/^\s*\^$/);				# cli cmd error marker
	return(1) if (/% unrecognized command/i);	# cli cmd error
	last if (/^$prompt/);
	return(1) if (/invalid (input|command) detected/i);

	# skip consecutive comment lines
	if (/^!\s*$/) {
	    next if ($comment);
	    ProcessHistory("CONFIG","","",$_);
	    $comment = 1;
	    next;
	}
	$comment = 0;

        next if (/^!(current configuration:|configuration last)/i);
        next if (/^vcs config-info/);
	if ((/^(.* password encrypted )\S+(.*)/ ||
	     /^(.* secret secret-encrypted )\w+( .*)/) && $filter_pwds >= 1) {
	    ProcessHistory("CONFIG", "", "", "$1<removed>$2\n");
	    next;
	}
	if (/^(snmp-server community \S+ )\S+(.*)/ && $filter_commstr >= 1) {
	    ProcessHistory("CONFIG", "", "", "!$1<removed>$2\n");
	    next;
	}
        ProcessHistory("CONFIG","","","$_");
	if (/^end/) {
	    $found_end = 1;
	}
    }
    ProcessHistory("CONFIG","","","\n");

    return(0);
}

# parses show vlan
sub ShowVlan {
    my($INPUT, $OUTPUT, $cmd) = @_;
    print STDERR "    In ShowVlan: $_" if ($debug);
    return basicFilter($INPUT, $OUTPUT, $cmd, "VLAN");
}

1;
