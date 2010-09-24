#!/usr/bin/perl -w

use strict;

use Getopt::Long;

my $fresh_file = "/opt/OV/newconfig/OVWIN-MIN/conf/trapd.conf";
my $current_file = "/etc/opt/OV/share/conf/C/trapd.conf";
my $do_anyway_file = undef;

my $task = "csv";

my $result = GetOptions("oob=s",\$fresh_file,
			"current=s",\$current_file,
		       "do-anyway=s",\$do_anyway_file);

use TrapdConfig;

my $fresh_trapd = new TrapdConfig($fresh_file);
my $current_trapd = new TrapdConfig($current_file);
my $do_anyway_trapd = defined $do_anyway_file ? new TrapdConfig($do_anyway_file) : undef;

my %fresh_oids;
my %current_oids;
my %do_anyway_oids;

my $oid;

foreach $oid ($fresh_trapd->all_event_oids()) {
  $fresh_oids{$oid} = $fresh_trapd->event_by_oid($oid);
}
foreach $oid ($current_trapd->all_event_oids()) {
  $current_oids{$oid} = $current_trapd->event_by_oid($oid);
}

if (defined $do_anyway_trapd) {
  foreach $oid ($do_anyway_trapd->all_event_oids()) {
    $do_anyway_oids{$oid} = $do_anyway_trapd->event_by_oid($oid);
  }
}

my $event;
my $tab = "\t";

if ($task eq "csv") {
  print "Enterprise\tSNMP Trap Oid\tEvent Description\tDefault Severity\tASG Suggested Severity\tAlphaWest Severity Decision\tCurrent Forwarding\tASG Suggested Forwarding\tAlphaWest Forwarding Decision\tLong description\n";
  foreach $oid (sort keys %current_oids) {
    $event = $current_oids{$oid};
    next if exists $fresh_oids{$oid} and not exists $do_anyway_oids{$oid};
    print $current_trapd->best_enterprise($oid);
    print $tab;
    print "$oid";
    print $tab;
    print $event->name();
    print $tab;
    print $event->severity();
    print $tab;
    print $tab;
    print $tab;
    print (defined $event->forwarding() ? $event->forwarding() : "");
    print $tab;
    print $tab;
    print $tab;
    print "\"";
    my $descr = $event->description();
    $descr =~ s/"/'/g;
    if (length($event->description) > 100) {
      $descr = substr($descr,0,100) . "...";
    }
    print $descr;
    print "\"";
    print "\n";
  }
}
