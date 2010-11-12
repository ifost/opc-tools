package OpcConfig::Template;

=head1 OpcConfig::Template

This module defines the class hierarchy of OpcConfig::Template, which is a base class
and subclasses for monitors, logfiles, etc.


=cut

use strict;

my $version = '$Id: OpcConfig.pm 1467 2010-09-24 01:40:02Z gregb $';

sub version { return $version; }

sub default_severity {
  my $self = shift;
  return $self->{"SEVERITY"};
}

=head2 $template->standard_initialisation()

Kind of pseudo-base class initialiser.

=cut

sub standard_initialisation {
  my $self = shift;
  $self->{"conditions"} = [];
  $self->{"next condition type"} = undef;
}


=head2 $template->next_condition_type($condition_type)

Set ths type of the next condition to be created when $template->add_condition(...) is
next called.

C<$condition_type> can be one of

=over

=item MSGCONDITIONS

=item SUPP_UNM_CONDITIONS

=item SUPPRESSCONDITIONS

=back

=cut

sub next_condition_type {
  my $self = shift;
  my $condition_type = shift;
  $self->{"next condition type"} = $condition_type;
  die "unknown condition type $condition_type"
    unless $condition_type =~ /^(MSGCONDITIONS|SUPP_UNM_CONDITIONS|SUPPRESSCONDITIONS)$/;
}


=head2 $template->store($keyword,$answer)

Read in a line, which probably has something to do with the template, rather than some
conditions.

=cut

sub store {
  my $self = shift;
  my $keyword = shift;
  my $answer = shift;
  $self->{$keyword} = $answer;
}



=head2 $template->kind()

Returns the kind of template. It can be one of:

=over

=item TEMPLATE_GROUP

=item SNMP

=item ...

=back

(virtual function)

=cut


=head2 $template->parent()

Returns the OpcConfig object which this is a member of.

=cut

sub parent {
  my $self = shift;
  return $self->{'parent'};
}

use OpcConfig::Template::Condition;

=head2 $template->add_condition($description)

Appends another condition to the template, with name $description. The type of
template condition depdends on the last call to $template->next_condition_type(...)


=cut

sub add_condition {
  my $self = shift;
  my $description = shift;
  my $condition_type = $self->{"next condition type"};
  my $t;
  my $kind = $self->kind();
  die unless defined $self->{"next condition type"};
  if ($condition_type eq 'MSGCONDITIONS') { $t = new OpcConfig::Template::Condition::MessageCondition($self,$description,$kind); }
  elsif ($condition_type eq 'SUPP_UNM_CONDITIONS') { $t = new OpcConfig::Template::Condition::SuppressUnlessCondition($self,$description,$kind); }
  elsif ($condition_type eq 'SUPPRESSCONDITIONS') { $t = new OpcConfig::Template::Condition::SuppressCondition($self,$description,$kind); }
  else { die "unknown condition type $condition_type"; }
  push (@{$self->{"conditions"}},$t);
  return $t;
}

sub conditions {
  my $self = shift;
  return @{$self->{"conditions"}};
}

sub set_description {
  my $self = shift;
  my $description = shift;
  $self->{"DESCRIPTION"} = $description;
}

sub description {
  my $self = shift;
  return $self->{"DESCRIPTION"};
}

######################################################################


package OpcConfig::Template::OpcmsgTemplate;

use base 'OpcConfig::Template';

sub new {
  my $class = shift;
  my $name = shift;
  my $parent = shift;
  my $self = {};
  $self->{'name'} = $name;
  $self->{'parent'} = $parent;
  bless $self,$class;
  $self->standard_initialisation();
  return $self;
}

sub kind { return 'OPCMSG'; }

sub csvformat {
  my $self = shift;
  my $indent = shift || 0;
  print "\t"x$indent;
  print "Name\tMatching text\tMessage text\tSeverity\n";
  my $msgcondition;
  foreach $msgcondition ($self->conditions()) {
    my $description = $msgcondition->description();
    my $match_text = $msgcondition->matching_text() || "(non-text match conditions)";
    my $severity = $msgcondition->generated_message_severity();
    print "\t"x$indent;
    print "$description\t$match_text\t";
    if (defined $severity) {
      my $outtext = $msgcondition->generated_message_text() || $match_text;
      print "$outtext\t$severity\n";
    } else {
      print "\t".$msgcondition->flowcontrol()."\n";
    }
  }
}



######################################################################


package OpcConfig::Template::LogfileTemplate;

use base 'OpcConfig::Template';

sub new {
  my $class = shift;
  my $name = shift;
  my $parent = shift;
  my $self = {};
  $self->{'name'} = $name;
  $self->{'parent'} = $parent;
  bless $self,$class;
}

sub kind { return 'LOGFILE'; }

sub csvformat {
  my $self = shift;
  my $indent = shift || 0;
  print "\t"x$indent;
  print "Name\tMatching text\tMessage text\tSeverity\n";
  my $msgcondition;
  foreach $msgcondition ($self->conditions()) {
    my $description = $msgcondition->description();
    my $match_text = $msgcondition->matching_text();
    my $severity = $msgcondition->generated_message_severity();
    print "\t"x$indent;
    print "$description\t$match_text\t";
    if (defined $severity) {
      my $outtext = $msgcondition->generated_message_text();
      print "$outtext\t$severity\n";
    } else {
      print "\t".$msgcondition->flowcontrol()."\n";
    }
  }
}


######################################################################


package OpcConfig::Template::MonitorTemplate;

use base 'OpcConfig::Template';

sub new {
  my $class = shift;
  my $name = shift;
  my $parent = shift;
  my $self = {};
  $self->{'name'} = $name;
  $self->{'parent'} = $parent;
  bless $self,$class;
  $self->standard_initialisation();
  return $self;
}

sub kind { return 'MONITOR'; }

sub csvformat {
  my $self = shift;
  my $indent = shift || 0;
  print "\t"x$indent;
  print "Name\tThreshold\tAlarm text\tSeverity\n";
  my $msgcondition;
  foreach $msgcondition ($self->conditions()) {
    my $description = $msgcondition->description();
    my $threshold = $msgcondition->threshold();
    my $severity = $msgcondition->generated_message_severity();
    my $outtext = $msgcondition->generated_message_text();
    print "\t"x$indent;
    if (defined $severity) {
      die unless defined $description;
      die unless defined $threshold;
      $outtext = "(Default monitor message)" unless defined $outtext;
      print "$description\t$threshold\t$outtext\t$severity\n";
    } else {
      print "$description\t\t$outtext\t\n";
    }
  }
}



######################################################################


package OpcConfig::Template::TemplateGroup;

sub store {
  my $self = shift;
  my $keyword = shift;
  my $answer = shift;
  if ($keyword =~ /MEMBER_(\w*)/) {
    my $member_type = $1;
    $member_type = 'SCHEDULE' if $member_type eq 'SCHED';
    $self->{'members'}->{$member_type} = [] 
      unless exists $self->{'members'}->{$member_type};
    push(@{$self->{'members'}->{$member_type}},$answer);
    return;
  }
  print STDERR "Don't really know what to do with $keyword = $answer, so fudging it.\n";
  $self->{'attributes'}->{$keyword} = $answer;
}

#my @possible_members = qw{ECS LOGFILE MONITOR OPCMSG SCHEDULE SNMP TEMPLATE_GROUP};

sub members {
  my $self = shift;
  my $template_type;
  my $template_name;
  my @answer;
  foreach $template_type (keys %{$self->{'members'}}) {
    foreach $template_name (@{$self->{'members'}->{$template_type}}) {
      push(@answer,[$template_type,$template_name]);
    }
  }
  return @answer;
}


=head1 $template_group->recurse()

Returns all templates inside this template group, expanding out template
groups recursively.

=cut

sub recurse {
  my $self = shift;
  my @answer;
  my @members = $self->members();
  my $member;
  my $template_name;
  my $template_type;
  my $template;
  my $parent = $self->{'parent'};
  print STDERR "Members are ".join(" ",@members)."\n";
  foreach $member (@members) {
    ($template_type,$template_name) = @$member;
    my $template=$parent->get_template($template_type,$template_name);
    print STDERR "EXAMINING $template_name\n";
    if ($template_type eq 'TEMPLATE_GROUP') {
      print STDERR "EXPANDING $template_name\n";
      push(@answer,$template->recurse());
    } else {
      push(@answer,$template);
    }
  }
  return @answer;
}

sub new {
  my $class = shift;
  my $name = shift;
  my $parent = shift;
  my $self = {};
  $self->{'name'} = $name;
  $self->{'attributes'} = {};
  $self->{'members'} = {};
  $self->{'parent'} = $parent;
  bless $self,$class;
  return $self;
}

sub set_description {
  my $self = shift;
  my $description = shift;
  $self->{"DESCRIPTION"} = $description;
}

sub kind { return 'TEMPLATE_GROUP'; }


sub csvformat {
  my $self = shift;
  my $indent = shift || 0;
  my $template_type;
  my $template_name;
  my $template;
  my $subtemplate;
  my $parent = $self->{"parent"};
  print " "x$indent;
  print "-- TEMPLATE GROUP ".$self->{"name"}."\n";
  foreach $template_type (keys %{$self->{'members'}}) {
    next if $template_type eq 'TEMPLATE_GROUP'; # do them last
    foreach $template_name (@{$self->{'members'}->{$template_type}}) {
      $subtemplate = $parent->get_template($template_type,$template_name);
      print " "x($indent+1);
      print " $template_type template $template_name\n";
      $subtemplate->csvformat(1);
    }
  }
  if (exists $self->{'members'}->{'TEMPLATE_GROUP'}) {
    foreach $template_name (@{$self->{'members'}->{'TEMPLATE_GROUP'}}) {
      $subtemplate = $parent->get_template('TEMPLATE_GROUP',$template_name);
      $subtemplate->csvformat($indent+1);
    }
  }
}

######################################################################

package OpcConfig::Template::ECSTemplate;

#use base 'OpcConfig::Template';
# Not sure about this one

sub new {
  my $class = shift;
  my $name = shift;
  my $parent = shift;
  my $self = {};
  $self->{'name'} = $name;
  $self->{'parent'} = $parent;
  bless $self,$class;
}

sub kind { return 'ECS'; }

######################################################################

package OpcConfig::Template::ScheduleTemplate;

use base 'OpcConfig::Template';

sub new {
  my $class = shift;
  my $name = shift;
  my $parent = shift;
  my $self = {};
  $self->{'name'} = $name;
  $self->{'parent'} = $parent;
  bless $self,$class;
  $self->standard_initialisation();
  $self->{'current trigger'} = undef;
  $self->{'BEFORE'} = {};
  $self->{'SUCCESS'} = {};
  $self->{'FAILURE'} = {};
  $self->{'reading generated message attributes'} = 0;
  return $self;
}

sub kind { return 'SCHEDULE'; }

sub start_reading_generated_message_attributes {
  my $self = shift;
  $self->{'reading generated message attributes'} = 1;
}

sub store {
  my $self = shift;
  my $keyword = shift;
  my $answer = shift;
  if ($keyword =~ /(BEFORE|SUCCESS|FAILURE)/) { $self->{'current trigger'} = $1; return; }
  if ($self->{'reading generated message attributes'} == 1) {
    $self->{$self->{'current trigger'}}->{$keyword} = $answer;
  } else {
    $self->{$keyword} = $answer;
  }
}

sub csvformat {
  return;

  # The follow code is completely broken.
  # Instead of trying to fix it, we silently ignore schedule templates.
  my $self = shift;
  my $indent = shift || 0;
  print "\t"x$indent;
  print "Name\tProgram\n";
  my $msgcondition;
  foreach $msgcondition ($self->conditions()) {
    my $description = $msgcondition->description();
    my $program = $msgcondition->{"SCHEDPROG"};
    print "$description\t$program\n";
  }
  # To do: this is not quite complete. It should print out the
  # schedule of when things are going to be run, and what messages
  # it generates when we do.
}

######################################################################

package OpcConfig::Template::SnmpTrapTemplate;

use base 'OpcConfig::Template';

sub new {
  my $class = shift;
  my $name = shift;
  my $parent = shift;
  my $self = {};
  $self->{'name'} = $name;
  $self->{'parent'} = $parent;
  bless $self,$class;
  $self->standard_initialisation();
  return $self;

}

sub display {
  my $self = shift;
  my $k;
  foreach $k (keys %$self) {
    if ($k eq 'conditions') {
      print "Conditions: \n";
      my $msgcondition;
      foreach $msgcondition (@{$self->{'conditions'}}) {
	unless (defined $msgcondition) {
	  print STDERR join("; ",@{$self->{'conditions'}});
	  print "\n";
	  die;
	}
	$msgcondition->display();
      }
    } else {
      print "$k -> ".$self->{$k}."\n";
    }
  }
}

sub kind { return 'SNMP'; }


sub csvformat {
  my $self = shift;
  my $indent = shift || 0;
  print "\t" x $indent;
  print "SNMP Trap Oid\tAlarm Text\tSeverity\tHelp Text\n";
  my $msgcondition;
  foreach $msgcondition (@{$self->{'conditions'}}) {
    print "\t" x $indent;
    print $msgcondition->snmpv2oid();
    print "\t";
    my $severity = $msgcondition->generated_message_severity();
    if (defined $severity) {
      print $msgcondition->generated_message_text();
      print "\t";
      print $severity;
      print "\t";
      print $msgcondition->generated_message_helptext();
    } else {
      print "Suppressed";
    }
    print "\n";
  }
}

1;
