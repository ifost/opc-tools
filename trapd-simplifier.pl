#!/usr/bin/perl -w

use strict;

use Getopt::Long;

my $current_file = "/etc/opt/OV/share/conf/C/trapd.conf";
my $oid_file = undef;

my $result = GetOptions("trapd=s",\$current_file,
		       "oid-file=s",\$oid_file);

die "Must specify --oid-file" unless defined $oid_file;
use TrapdConfig;

my $current_trapd = new TrapdConfig($current_file);

open(OIDFILE,$oid_file) || die "Can't read $oid_file: $!";

my $severity;
my $oid;
my $alarm_format;

my %oid_redefs;
my %format_redefs;

while (<OIDFILE>) {
  next if /^#/;
  next if /^\s*$/;
  if (/^\s*([.0-9*]+)[, \t](Normal|Suppress|Warning|Minor|Major|Critical)\s*[, \t]([^ \t].*)\s*$/i) {
    $oid = $1;
    $severity = $2;
    $alarm_format = $3;
    $alarm_format =~ s/^\s+//;
    $alarm_format =~ s/\s+$//;
    if ($oid !~ /^\./) { $oid = ".$oid"; }
    $oid_redefs{$oid} = ucfirst (lc $severity);
    $format_redefs{$oid} = $alarm_format eq "" ? undef : $alarm_format;
    next;
  }
  if (/^\s*([.0-9*]+)[, \t](Normal|Suppress|Warning|Minor|Major|Critical)\s*$/i) {
    $oid = $1;
    $severity = $2;
    if ($oid !~ /^\./) { $oid = ".$oid"; }
    $oid_redefs{$oid} = ucfirst (lc $severity);
    $format_redefs{$oid} = undef;
    next;
  }
  if (/^\s*([.0-9*]+)\s*$/) {
    $oid = $1;
    if ($oid !~ /^\./) { $oid = ".$oid"; }
    $severity = "unchanged";
    $oid_redefs{$oid} = undef;
    $format_redefs{$oid} = undef;
    next;
  }
  die "Could not understand line $.: $_";
}


my $event;
my $event_name;
my $category;
my $description;

print "VERSION 3\n";
foreach $oid (sort $current_trapd->all_event_oids()) {
  #print "WORKING ON $oid\n" if $oid =~ /.1.3.6.1.6.3.1.1.5.[34]/;
  next unless exists $oid_redefs{$oid};
  #print "CONINUING ON $oid\n" if $oid =~ /.1.3.6.1.6.3.1.1.5.[34]/;

  $event = $current_trapd->event_by_oid($oid);
  $event_name = $event->name();
  $severity = $oid_redefs{$oid} ne "unchanged" ?
    $oid_redefs{$oid} : $event->severity();

  next if $severity eq 'Suppress';
  if ((exists $format_redefs{$oid}) and (defined $format_redefs{$oid})) {
    $alarm_format = $format_redefs{$oid};
  } else {
    $alarm_format = $event->alarm_format();
  }

  $description = $event->description();
  $category = $event->category();
  if ($category eq 'LOGONLY') {
    $category = 'Status Alarms';
  }

  print "EVENT $event_name $oid \"$category\" $severity\n";
  print "FORMAT $alarm_format\n";
  print "SDESC\n";
  print $description;
  print "EDESC\n";
  print "#\n#\n#\n";
}
