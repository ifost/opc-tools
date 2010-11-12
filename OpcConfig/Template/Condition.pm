package OpcConfig::Template::Condition;

=head1 OpcConfig::Template::Condition

This module defines the class structur for OpcConfig::Template::Condition

=cut

use strict;

my $version = '$Id: OpcConfig.pm 1467 2010-09-24 01:40:02Z gregb $';

sub version { return $version; }

sub snmpv2oid {
  my $self = shift;
  die "Attempting to display oid of ".$self->{"KIND"}." condition" 
    unless $self->{"KIND"} eq "SNMP";
  my $matching = $self->{"ATTRIBUTES TO MATCH"};
  # Default to mib2 snmpTraps if enterprise is not defined.
  my $enterprise = exists $matching->{'$e'} ? $matching->{'$e'} : ".1.3.6.1.6.3.1.1.5";
  my $generic = $matching->{'$G'};
  my $specific = $matching->{'$S'};
  if (!defined $specific and $generic == 6) { $specific = "*"; }
  die "Condition ".$self->{"DESCRIPTION"}." is missing \$G" unless defined $generic;
  my %snmp1to2 = ( 6 => 0, 0 => 1, 1 => 2, 2 => 3, 3 => 4, 4 => 5, 5 => 6 );
  die "Could not convert '$enterprise' '$generic' '$specific' to snmp v2" unless 
    exists $snmp1to2{$generic};
  my $v2;
  if ($generic == 6) {
    $v2 = $enterprise.".".$snmp1to2{$generic}.".".$specific;
  } else {
    $v2 = $enterprise.".".$snmp1to2{$generic};
  }
  return $v2;
}


sub matching_text { my $self = shift; return $self->{"ATTRIBUTES TO MATCH"}->{"TEXT"}; }

sub threshold { my $self = shift; return $self->{"ATTRIBUTES TO MATCH"}->{"THRESHOLD"}; }

sub description { my $self = shift; return $self->{"DESCRIPTION"}; }

sub display;

sub generated_message_severity { return undef; }



package OpcConfig::Template::Condition::SuppressCondition;
use base 'OpcConfig::Template::Condition';

sub new {
  my $class = shift;
  my $parent = shift;
  my $self = {};
  my $description = shift;
  my $kind = shift;
  $self->{"DESCRIPTION"} = $description;
  $self->{"ATTRIBUTES TO MATCH"} = {};
  $self->{"KIND"} = $kind;
  $self->{"PARENT"} = $parent;
  bless $self,$class;
  return $self;
}

sub display {
  my $self = shift;
  print " Suppress condition (".$self->{"DESCRIPTION"}."): \n";
  my $k;
  foreach $k (keys %$self) { print "    $k -> ".$self->{$k}."\n"; }
}

sub store {
  my $self = shift;
  my $k = shift;
  my $v = shift;
  $self->{"ATTRIBUTES TO MATCH"}->{$k} = $v;
}

sub flowcontrol { return "Suppress"; }

sub generated_message_text { return "(Message suppressed)"; }


package OpcConfig::Template::Condition::SuppressUnlessCondition;
use base 'OpcConfig::Template::Condition';

sub new {
  my $class = shift;
  my $parent = shift;
  my $self = {};
  my $description = shift;
  my $kind = shift;

  $self->{"DESCRIPTION"} = $description;
  $self->{"ATTRIBUTES TO MATCH"} = {};
  $self->{"KIND"} = $kind;
  $self->{"PARENT"} = $parent;
  bless $self,$class;
  return $self;
}

sub display {
  my $self = shift;
  print " Suppress unless condition (".$self->{"DESCRIPTION"}."): \n";
  my $k;
  foreach $k (keys %$self) { print "    $k -> ".$self->{$k}."\n"; }
}

sub store {
  my $self = shift;
  my $k = shift;
  my $v = shift;
  $self->{"ATTRIBUTES TO MATCH"}->{$k} = $v;
}

sub flowcontrol { return "SuppressUnless"; }

sub generated_message_text { return "(Following messages suppressed unless)"; }

package OpcConfig::Template::Condition::MessageCondition;
use base 'OpcConfig::Template::Condition';

sub new {
  my $class = shift;
  my $parent = shift;
  my $self = {};
  my $description = shift;
  my $kind = shift;
  $self->{"DESCRIPTION"} = $description;
  $self->{"ATTRIBUTES TO MATCH"} = {};
  $self->{"MESSAGE TO GENERATE"} = {};
  $self->{"currently reading"} = "ATTRIBUTES TO MATCH";
  $self->{"KIND"} = $kind;
  $self->{"PARENT"} = $parent;
  bless $self,$class;
  return $self;
}

sub start_reading_generated_message_attributes {
  my $self = shift;
  $self->{"currently reading"} = "MESSAGE TO GENERATE";
}


sub display {
  my $self = shift;
  print " Message condition (".$self->{"DESCRIPTION"}."): \n";
  my $k;
  print "   When the following conditions occur: \n";
  foreach $k (keys %{$self->{"ATTRIBUTES TO MATCH"}}) {
    print "     $k -> ".$self->{"ATTRIBUTES TO MATCH"}->{$k}."\n";
  }
  print "   Generate the following message: \n";
  foreach $k (keys %{$self->{"MESSAGE TO GENERATE"}}) {
    print "     $k -> ".$self->{"MESSAGE TO GENERATE"}->{$k}."\n";
  }
}

sub store {
  my $self = shift;
  my $k = shift;
  my $v = shift;
  my $which_to_set = $self->{"currently reading"};
  $self->{$which_to_set}->{$k} = $v;
}

sub generated_message_severity {
  my $self = shift;
  my $msggen = $self->{"MESSAGE TO GENERATE"};
  my $severity = $msggen->{"SEVERITY"};
  my $parent = $self->{"PARENT"};
  $severity = $parent->default_severity unless defined $severity;
  $severity = "Unknown" unless defined $severity;
  die "Weird severity in condition ".$self->description().": $severity" unless $severity =~ /Normal|Warning|Minor|Major|Critical|Unknown/i;
  return $severity;
}


sub generated_message_text {
  my $self = shift;
  my $msggen = $self->{"MESSAGE TO GENERATE"};
  my $text = $msggen->{"TEXT"};
  return $text;
  # Should check for a default in the parent
}

sub generated_message_helptext {
  my $self = shift;
  my $msggen = $self->{"MESSAGE TO GENERATE"};
  my $text = $msggen->{"HELPTEXT"};
  return defined $text ? $text : "";
  # Should check for a default in the parent
}

sub flowcontrol { return "Message"; }
1;
