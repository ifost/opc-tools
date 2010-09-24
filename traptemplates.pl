#!/usr/bin/perl -w

use OpcConfig;

my $opcconfig = new OpcConfig();

my $filename;
foreach $filename (@ARGV) { $opcconfig->read_file($filename); }

my $template = $opcconfig->get_template("SNMP","CMC_SNMP_FULL Traps");

my $condition;
foreach $condition ($template->conditions()) {
  my $severity = $condition->generated_message_severity();
  next unless defined $severity;
  print $condition->snmpv2oid()."\t$severity\n";
}
