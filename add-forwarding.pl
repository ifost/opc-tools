#!/usr/bin/perl -w

use strict;

open(FORWARDING_LIST,$ARGV[0]) || die "Can't open $ARGV[0]: $!";


my %traps_to_mod;

while (<FORWARDING_LIST>) {
  chomp;
  next if /^\s*$/;
  die "Line $. of $ARGV[0] doesn't look like a v2 trap oid" unless /^[0-9.]*$/;
  $traps_to_mod{$_} = 1;
}
close(FORWARDING_LIST);

open(TRAP_FILE,$ARGV[1]) || die "Can't open $ARGV[1]: $!";

my $do_insert = 0;
while (<TRAP_FILE>) {
  if (/EVENT\s+(\w+)\s+([0-9.]+)\s+/) {
    my $oid = $2;
    $do_insert = exists $traps_to_mod{$oid};
    print;
    next;
  }
  if ($do_insert and /SDESC/) {
    print "FORWARD emc-central-nnm01\n";
    print;
    $do_insert = 0;
    next;
  }
  print;
  next;
}

