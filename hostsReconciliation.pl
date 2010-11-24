#!/usr/bin/perl -w

use strict;

=head1 NAME

hostsReconciliation.pl

=head1 SYNOPSIS

C<hostsReconciliation.pl> I<hostsfile>

=head1 DESCRIPTION

C<hostsReconciliation.pl> reads through the I<hostsfile> argument and
looks for all IP addresses it finds there. It then prints out a
sequence of shell commands which will make sure the name and label matches
what is in the hosts file.

=head1 TO-DO

It doesn't cope with IPv6 addresses in the host file. But I don't think
OVO copes with that either.

=cut

my $sudo = $< == 0 ? "" : "sudo"; 

if (defined $ARGV[0] and $ARGV[0] !~ /^\s*$/) {
    open(HOSTSFILE,"<$ARGV[0]") || die "Can't open $ARGV[0]";
} else {
    open(HOSTSFILE,"/etc/hosts") || die "Can't open /etc/hosts";
}

my %ip_to_hostname;
while (<HOSTSFILE>) {
    s/#.*//;
    next if /^\s*$/;
    die "Invalid line: $_ at $." unless /^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\s*(\w[^.\s]*)/;
    $ip_to_hostname{$1} = $2;
}


print STDERR "Using cache file .nodelist\n" if -e ".nodelist";
print STDERR "Getting list of all nodes by running opcnode\n" unless -e '.nodelist';

my @nodes_to_report_on;
system("$sudo opcnode -list_nodes > .nodelist") unless -e ".nodelist";
open(NODES_LIST,".nodelist") || die "Couldn't run opcnode -list_nodes";
my $ip;
my $node;
my $label;
my $shortname;
while (<NODES_LIST>)  {
 if (/^Name\s*=\s*(.*)\s*$/) { 
     $node = $1; 
     $shortname=uc $node; 
     $shortname =~ s/\..*//;
     next; 
 }
 if (/^Label\s*=\s*(.*)\s*$/) { $label = $1; next; }
 if (/^IP-Address\s*=\s*(.*)\s*$/) { 
   $ip = $1;
   next unless exists $ip_to_hostname{$ip};
   next if $shortname eq uc $ip_to_hostname{$ip} 
        and uc $label eq uc $ip_to_hostname{$ip};
   print "$sudo opcchgaddr -label $ip_to_hostname{$ip} IP $ip $node IP $ip $ip_to_hostname{$ip}\n";
   if ($label =~ /^\s*$/) { print "# Because it had no label\n"; }
   else { print "# Because it was Name=$node, Label=$label, IP-Address=$ip\n"; }
   print "\n";
 }
}

