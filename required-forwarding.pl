#!/usr/bin/perl -w

use strict;

# This program figures out what mangling traps need to have "FORWARD" set on them


use Getopt::Long;
use TrapdConfig;
use OpcConfig;

my $trapd_file = "/etc/opt/OV/share/conf/C/trapd.conf";
my $trap_downloads = undef;
my $trap_template = undef;

my $result = Getopt::Long::GetOptions('trapd=s',\$trapd_file,
				      'opcdwn=s',\$trap_downloads,
				      'template-name=s',\$trap_template);

die "Usage: $0 --trapd=... --opcdwn=... --template-name=..." unless $result;
die "Must specify --opcdwn" unless defined $trap_downloads;
die "Must specify --template-name" unless defined $trap_template;

my $trapd = new TrapdConfig($trapd_file);
my $opcconfig = new OpcConfig();
$opcconfig->read_dir($trap_downloads);

my $template = $opcconfig->get_template("SNMP",$trap_template);
die "No such trap template $trap_template" unless defined $template;

my $msgcondition;
my %alarmed_oids;

foreach $msgcondition ($template->conditions) {
  my $severity;
  $severity = $msgcondition->generated_message_severity();
  next unless defined $severity;
  $alarmed_oids{$msgcondition->snmpv2oid()} = $severity;
}

my $oid;
my $event;
my $tab = "\t";

print "SNMP Trap Name\tSNMP Trap Oid\tTrapd Severity\tOVO Severity\n";
foreach $oid (sort $trapd->all_event_oids()) {
  if (exists $alarmed_oids{$oid}) {
    $event = $trapd->event_by_oid($oid);
    print $event->name();
    print $tab;
    print $oid;
    print $tab;
    print $event->severity();
    print $tab;
    print $alarmed_oids{$oid};
    print "\n";
  }
}


