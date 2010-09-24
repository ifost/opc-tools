package OpcConfig;

=head1 OpcConfig

This module can read the dumps you get out of OpC / Operations Manager /
VantagePoint Operations / Operations Manager for Unix when you run
C<opccfgdwn>.

=cut

use strict;

my $version = '$Id: OpcConfig.pm 1467 2010-09-24 01:40:02Z gregb $';

sub version { return $version; }

sub new {
  my $class = shift;
  my $self = {};
  bless $self;
}

=head2 read_file

This method reads one of the .dat files you get in the output directory
of C<opccfgdwn>.

=cut


sub read_file {
  my $self = shift;
  my $filename = shift;
  my %msgi = ();
  my $current_template;
  my $current_condition;
  my $workspace = "";
  my $pre_workspace = "";
  my $line;
  my $have_started_on_conditions = 0;
  my $workspace_is_continued = 0;
  open(FILE,$filename) || die "Could not read $filename";
  while ($line = <FILE>) {
    next if $line =~ /^\s*$/;
    chomp $line;
    if ($pre_workspace ne "") {
      $workspace = $pre_workspace . "\n". $line;
    } else {
      $workspace = $line;
    }
    $pre_workspace = "";

    # (?<!\\)" means any " which is not part of \"

    if ($workspace =~ /(?<!\\)"/) {
      my $temp_workspace = " $workspace"; # so that a leading quote is not at the line beginning
      $temp_workspace =~ s/(?<!\\)""//g;  # get rid of "" because it's too confusing and difficult
      my @quote_count = split(/(?<!\\)"/,$temp_workspace);
      if ($temp_workspace =~ /(?<!\\)"$/) {
	push(@quote_count,"");
      }
      my $number_of_quotes = $#quote_count;
      if ($number_of_quotes % 2 == 1) {
	#line incomplete
	#print STDERR "$workspace is incomplete because $#quote_count : ";
	#print STDERR join(" **\"** ",@quote_count);
	#print STDERR "\n";
	$pre_workspace = $workspace;
	#if ($workspace !~ /HELPTEXT/) {
	#  print STDERR "Continuing workspace $workspace because it has $number_of_quotes quote character\n";
	#  print STDERR "And I had to add one because of a trailing quote\n" if $workspace =~ /(?<!\\)"$/;
	#}
	$workspace_is_continued = 1;
	next;
      }
    }
    #print STDERR "Continued workspace $workspace\n\n" if $workspace_is_continued and $workspace !~ /HELPTEXT/;
    $workspace_is_continued = 0;

    next if $workspace =~ /SYNTAX_VERSION/;
    if ($workspace =~ /^\s*(OPCMSG|LOGFILE|MONITOR|TEMPLATE_GROUP|ECS|SCHEDULE|SNMP)\s*"(.*)"/) {
      my $template_type = $1;
      my $template_name = $2;
      $self->{$template_type} = {} unless exists $self->{$template_type};
      $current_template = make_template($template_name,$template_type);
      $current_condition = undef;
      $self->{$template_type}->{$template_name} = $current_template;
      $have_started_on_conditions = 0;
      next;
    }

    if ($workspace =~ /^\s*MEMBER_TEMPLATE_GROUP\s*"(.*)"/) {
      $current_template->{"MEMBER_TEMPLATE_GROUP"} = [] unless exists $current_template->{"MEMBER_TEMPLATE_GROUP"};
      push(@{$current_template->{"MEMBER_TEMPLATE_GROUP"}},$1);
      next;
    }

    if ($workspace =~ /^\s*(SUPP_UNM_CONDITIONS|SUPPRESSCONDITIONS|MSGCONDITIONS)/) {
      my $condition_type = $1;
      $current_template->next_condition_type($condition_type);
      $have_started_on_conditions = 1;
      #print STDERR "Line $. $condition_type     \r";
      next;
    }
    if ($workspace =~ /(SUPP_UNM_CONDITIONS|SUPPRESSCONDITIONS|MSGCONDITIONS)/) {
      die "Error handling workspace $workspace at $.";
    }

    if ($workspace =~ /^\s*DESCRIPTION\s*"(.*)"\s*$/) {
      if ($have_started_on_conditions) {
	$current_condition = $current_template->add_condition($1);
      } else {
	# Must be the description of the template
	$current_template->{"DESCRIPTION"} = $1;
      }
      next;
    }

    if ($workspace =~ /^\s*SET\s*$/) {
      $current_condition->start_reading_generated_message_attributes();
      next;
    }

    if ($workspace =~ /^\s*([A-Za-z0-9\$]+)\s*(.*)\s*$/) {
      my $keyword = $1;
      my $answer = $2; 
      # Remove quote characters, and remove double blanks.
      $answer =~ s/^\s*"(.*)"\s*$/$1/;

      if ($keyword eq "SEVERITY") { 
	# e.g. a windows event logfile or opcmsg kind of match
	# then don't care about order
	$answer = join(" ",sort split(/\s+/,$answer));
      } else {
	# then don't care about too much whitespace
	$answer = join(" ",split(/\s+/,$answer));
      }

      if (defined $current_condition) {
	$current_condition->store($keyword,$answer);
      } else {
	$current_template->{$keyword} = $answer;
      }
     #die "$workspace" if $answer =~ /"/ and not $answer =~ /".*"/;
    }
  }
}


sub print_brief_list {
  my $self = shift;
  my $template_name;
  my $template_type;
  foreach $template_type (sort keys %$self) {
    foreach $template_name (sort keys %{$self->{$template_type}}) {
      print "$template_type: $template_name\n";
    }
  }
}


sub get_template {
  my $self = shift;
  my $template_type = shift;
  my $template_name = shift;
  return $self->{$template_type}->{$template_name};
}

sub show_differences {
  my $issue_count = 1;
  my $templates1_name = shift;
  my $templates1 = shift;
  my $templates2_name = shift;
  my $templates2 = shift;
  my $template_name;
  my $template_type;
  my @template_types = sort (keys %$templates1, keys %$templates2);
  my @template_names;

  my $previous_template_type = "";
  my $previous_template_name = "";

 TEMPLATE_TYPE:
  foreach $template_type (@template_types) {
    next TEMPLATE_TYPE if $previous_template_type eq $template_type;
    $previous_template_type = $template_type;

    # If you do care about differences in template groups, comment out
    # the next line.
    next TEMPLATE_TYPE if $template_type eq "TEMPLATE_GROUP";

    unless (exists $templates1->{$template_type}) {
      print "\nDIFFERENCE ".($issue_count++). ": $templates1_name does not have any $template_type templates, and $templates2_name does.\n";
      next TEMPLATE_TYPE;
    }

    unless (exists $templates2->{$template_type}) {
      print "\nDIFFERENCE ".($issue_count++).": $templates2_name does not have any $template_type templates, and $templates1_name does.\n";
      next TEMPLATE_TYPE;
    }

    my @template1_names = keys %{$templates1->{$template_type}};
    my @template2_names = keys %{$templates2->{$template_type}};

    @template_names = sort (@template1_names,@template2_names);

    $previous_template_name = "";
  TEMPLATE_NAME:
    foreach $template_name (@template_names) {
      next TEMPLATE_NAME if $previous_template_name eq $template_name;
      $previous_template_name = $template_name;

      unless (exists $templates1->{$template_type}->{$template_name}) {
	print "\nDIFFERENCE ".($issue_count++).": $templates1_name does not have a $template_type template called \"$template_name\"\n";
	next TEMPLATE_NAME;
      }

      unless (exists $templates2->{$template_type}->{$template_name}) {
	print "\nDIFFERENCE ".($issue_count++).": $templates2_name does not have a $template_type template called \"$template_name\"\n";
	next TEMPLATE_NAME;
      }

      #print "$templates1_name and $templates2_name both have a $template_type template called $template_name\n";

      my $ct1 = $templates1->{$template_type}->{$template_name};
      my $ct2 = $templates2->{$template_type}->{$template_name};

      my @attrs1 = keys %$ct1;
      my @attrs2 = keys %$ct2;

      my $attr;
      my $previous_attr = "";
    ATTRIBUTE:
      foreach $attr (sort (@attrs1,@attrs2)) {
	next if $previous_attr eq $attr;
	$previous_attr = $attr;
	next if $attr =~ /MSGCONDITIONS/; # handle that later
	next if $attr =~ /SUPP_UNM_CONDITIONS/; # handle that later too
	next if $attr =~ /HELPTEXT/; # ignore it
	next if $attr =~ /MEMBER_TEMPLATE_GROUP/; # ignore it (should fix this)

	if ($attr eq "SEVERITY") {
	  # Then be a little less grumpy if things aren't around.
	  $ct1->{"SEVERITY"} = "unknown" unless exists $ct1->{"SEVERITY"};
	  $ct2->{"SEVERITY"} = "unknown" unless exists $ct2->{"SEVERITY"};
	}

	unless (exists $ct1->{$attr}) {
	  print "\nDIFFERENCE ".($issue_count++). ": $templates1_name has a $template_type template called \"$template_name\" (like $templates2_name does), but it does not have a \"$attr\" attribute\n";
	  next ATTRIBUTE;
	}


	unless (exists $ct2->{$attr}) {
	  print "\nDIFFERENCE ".($issue_count++). ": $templates2_name has a $template_type template called \"$template_name\" (like $templates1_name does), but it does not have a \"$attr\" attribute\n";
	  next ATTRIBUTE;
	}
      }

      if (!defined $ct1->{"MSGCONDITIONS"} &&
	  !defined $ct2->{"MSGCONDITIONS"}) {
	# shrug, OK.
	next TEMPLATE_NAME;
      }

      if (!defined $ct1->{"MSGCONDITIONS"}) {
	print "\nDIFFERENCE ".($issue_count++). ": $templates1_name and $templates2_name both have a $template_type template called \"$template_name\" but $templates1_name has no conditions defined.\n";
	next TEMPLATE_NAME;
      }

      if (!defined $ct2->{"MSGCONDITIONS"}) {
	print "\nDIFFERENCE ".($issue_count++). ": $templates1_name and $templates2_name both have a $template_type template called \"$template_name\" but $templates2_name has no conditions defined.\n";
	next TEMPLATE_NAME;
      }

      # Get out message conditions;
      my @msgconds1 = @{$ct1->{"MSGCONDITIONS"}};
      my @msgconds2 = @{$ct2->{"MSGCONDITIONS"}};

      my $cond;
      my %msgconds1;
      my %msgconds2;
      my $descr;
      my %positions1;
      my %positions2;
      my $i = 1;
      my %by_condition_id1;
      my %by_condition_id2;

      my $condition_id;

      foreach $cond (@msgconds1) { 
	$descr = $cond->{"DESCRIPTION"};
	$descr =~ s/^VMSPI-\d+:? //;
	$descr =~ s/\s*<=?\s*/</g;
	$descr =~ s/\s*>=?\s*/>/g;
	$msgconds1{$descr} = $cond;
	$positions1{$descr} = $i++;

	$condition_id = $cond->{"CONDITION_ID"};
	$by_condition_id1{$condition_id} = $cond;
      }

      $i = 1;
      foreach $cond (@msgconds2) {
	$descr = $cond->{"DESCRIPTION"};
	$descr =~ s/^VMSPI-\d+:? //;
	$descr =~ s/\s*<=?\s*/</g;
	$descr =~ s/\s*>=?\s*/>/g;
	$msgconds2{$descr} = $cond;
	$positions2{$descr} = $i++;

	$condition_id = $cond->{"CONDITION_ID"};
	$by_condition_id2{$condition_id} = $cond;
      }

      my @all_descrs = sort (keys %msgconds1,keys %msgconds2);
      my $condition_names_differ = 0;
      my $condition_orders_differ = 0;
      my @missing1;
      my @missing2;
      my @out_of_order;

    MESSAGE_CONDITION:
      foreach $descr (@all_descrs) {
	unless (exists $msgconds1{$descr}) {
	  push(@missing1,$descr);
	  next MESSAGE_CONDITION;
	}
	unless (exists $msgconds2{$descr}) {
	  push(@missing2,$descr);
	  next MESSAGE_CONDITION;
	}
	if ($positions1{$descr} != $positions2{$descr}) {
	  push(@out_of_order,$descr);
	}
      }

      if ($#missing1 > -1) {
	print "\nDIFFERENCE ".($issue_count++). ": $templates1_name and $templates2_name both have a $template_type template\n called \"$template_name\" but the following conditions were missing from $templates1_name:\n\t| ";
	print join(";\n\t| ",@missing1);
	print "\n";
      }
      if ($#missing2 > -1) {
	print "\nDIFFERENCE ".($issue_count++). ": $templates1_name and $templates2_name both have a $template_type template\n called \"$template_name\" but the following conditions were missing from $templates2_name:\n\t| ";
	print join(";\n\t| ",@missing2);
	print "\n";
      }

      if ($#out_of_order > -1 and $#missing1 == -1 and $#missing2 == -1) {
	print "\nDIFFERENCE ".($issue_count++). ": $templates1_name and $templates2_name both have a $template_type template\n called \"$template_name\", but there were position and/or ordering differences";
	#print ":\n\t| ";
	#print join(";\n\t| ",map ($_->{"DESCRIPTION"},@msgconds1));
	#print "\n\t\tversus\n\t| ";
	#print join(";\n\t| ",map ($_->{"DESCRIPTION"},@msgconds2));
	print "\n";
      }

    CONDITION_INDEX:
      for($i=0;$i <= $#msgconds1 and $i <= $#msgconds2;$i++) {
	if ($i == $#msgconds1+1) {
	  print "\nDIFFERENCE ".($issue_count++). ": $templates1_name and $templates2_name both have a $template_type template called $template_name but $templates1_name only has $i conditions.\n";
	  last CONDITION_INDEX;
	}
	if ($i == $#msgconds2+1) {
	  print "\nDIFFERENCE ".($issue_count++). ": $templates1_name and $templates2_name both have a $template_type template called $template_name but $templates2_name only has $i conditions.\n";
	  last CONDITION_INDEX;
	}

	my $cond_attr;
	my $m1 = $msgconds1[$i];
	my $m2;
	my $match_method;
	my $match_text;
	
	# Can we match on condition ID?
	if (exists $m1->{"CONDITION_ID"}) {
	  $condition_id = $m1->{"CONDITION_ID"};
	  if (exists $by_condition_id2{$condition_id}) {
	    $m2 = $by_condition_id2{$condition_id};
	    $match_method = "CONDITION_ID";
	    $match_text = "the condition (".($i+1).") with id = $condition_id (description: ".$m1->{"DESCRIPTION"}.")";
	    goto M2_MATCHED;
	  }
	}
	# Can we match by description?
	$descr = $m1->{"DESCRIPTION"};
	$descr =~ s/^VMSPI-\d+:? //;
	$descr =~ s/\s*<=?\s*/</g;
	$descr =~ s/\s*>=?\s*/>/g;
	if (exists $msgconds2{$descr}) {
	  $m2 = $msgconds2{$descr};
	  $match_method = "DESCRIPTION";
	  $match_text = "the condition (".($i+1).") with description '".$m1->{"DESCRIPTION"}."'";
	  goto M2_MATCHED;
	}

	# OK, well, give up and match by position
	$match_method = "POSITION";
	$match_text = "condition $i";
	$m2 = $msgconds2[$i];

      M2_MATCHED:
	my @cond_attrs = sort(keys %$m1,keys %$m2);
	my $prev_cond_attr = "";
	my @differing_attributes = ();
      CONDITION_ATTRIBUTE:
	foreach $cond_attr (@cond_attrs) {
	  next CONDITION_ATTRIBUTE if $cond_attr eq $prev_cond_attr;
	  $prev_cond_attr = $cond_attr;

	  next CONDITION_ATTRIBUTE if $cond_attr eq "DESCRIPTION";
	  next CONDITION_ATTRIBUTE if $cond_attr eq "SET HELPTEXT";
	  next CONDITION_ATTRIBUTE if $cond_attr eq "SET HELP";
	  next CONDITION_ATTRIBUTE if $cond_attr eq "CONDITION_ID";
	  next CONDITION_ATTRIBUTE if $cond_attr eq "SIGNATURE";
	  next CONDITION_ATTRIBUTE if $cond_attr eq "SET SIGNATURE";

	  push(@differing_attributes,$cond_attr)
	    unless exists $m1->{$cond_attr}
	       and exists $m2->{$cond_attr}
		 and ($m1->{$cond_attr} eq $m2->{$cond_attr});
	}
	

	if ($#differing_attributes > -1 and 
	    $match_method eq "POSITION") {
	  print "\nDIFFERENCE ".($issue_count++). ": $templates1_name and $templates2_name both have a $template_type template called\n $template_name but they differ on $match_text. This is probably because no condition was found in $templates2_name with a description of ".$m1->{"DESCRIPTION"}."\n";
	} elsif ($#differing_attributes > -1) {
	  print "\nDIFFERENCE ".($issue_count++). ": $templates1_name and $templates2_name both have a $template_type template called\n $template_name but $match_text differs in the following attributes: \n\t";
	  my @output;

	  foreach $cond_attr (@differing_attributes) {
	    push (@output,"| $cond_attr is ".
		  (exists $m1->{$cond_attr} 
		   ? ( $m1->{$cond_attr} =~ /^\s*$/  ? "{no value}" : $m1->{$cond_attr} )
		   : "{missing}").
		  " versus ".
		  (exists $m2->{$cond_attr}
		   ? ($m2->{$cond_attr} =~ /^\s*$/ ? "{no value}" : $m2->{$cond_attr} )
		      : "{missing}")
		  );
	  }
	  print join("\n\t",@output);
	  print "\n";
	}
      }
    }
  }
}

package OpcConfig::TemplateCondition;

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
  if ($generic != 6) {
    $v2 = $enterprise.".".$snmp1to2{$generic}.".".$specific;
  } else {
    $v2 = $enterprise.".".$snmp1to2{$generic};
  }
  return $v2;
}

sub description { my $self = shift; return $self->{"DESCRIPTION"}; }

sub display;

sub generated_message_severity { return undef; }

package OpcConfig::SuppressCondition;
use base 'OpcConfig::TemplateCondition';

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

package OpcConfig::SuppressUnlessCondition;
use base 'OpcConfig::TemplateCondition';

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


package OpcConfig::MessageCondition;
use base 'OpcConfig::TemplateCondition';

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



package OpcConfig::Template;

sub default_severity {
  my $self = shift;
  return $self->{"SEVERITY"};
}

sub standard_initialisation {
  my $self = shift;
  $self->{"conditions"} = [];
  $self->{"next condition type"} = undef;
}


sub next_condition_type {
  my $self = shift;
  my $condition_type = shift;
  $self->{"next condition type"} = $condition_type;
  die "unknown condition type $condition_type"
    unless $condition_type =~ /^(MSGCONDITIONS|SUPP_UNM_CONDITIONS|SUPPRESSCONDITIONS)$/;
}

sub add_condition {
  my $self = shift;
  my $description = shift;
  my $condition_type = $self->{"next condition type"};
  my $t;
  my $kind = $self->kind();
  die unless defined $self->{"next condition type"};
  if ($condition_type eq 'MSGCONDITIONS') { $t = new OpcConfig::MessageCondition($self,$description,$kind); }
  elsif ($condition_type eq 'SUPP_UNM_CONDITIONS') { $t = new OpcConfig::SuppressUnlessCondition($self,$description,$kind); }
  elsif ($condition_type eq 'SUPPRESSCONDITIONS') { $t = new OpcConfig::SuppressCondition($self,$description,$kind); }
  else { die "unknown condition type $condition_type"; }
  push (@{$self->{"conditions"}},$t);
  return $t;
}

sub conditions {
  my $self = shift;
  return @{$self->{"conditions"}};
}



package OpcConfig::OpcmsgTemplate;

use base 'OpcConfig::Template';

sub new {
  my $class = shift;
  my $name = shift;
  my $self = {};
  $self->{'name'} = $name;
  bless $self,$class;
  $self->standard_initialisation();
  return $self;
}

sub kind { return 'OPCMSG'; }

package OpcConfig::LogfileTemplate;

use base 'OpcConfig::Template';

sub new {
  my $class = shift;
  my $name = shift;
  my $self = {};
  $self->{'name'} = $name;
  bless $self,$class;
}

sub kind { return 'LOGFILE'; }


package OpcConfig::MonitorTemplate;

use base 'OpcConfig::Template';

sub new {
  my $class = shift;
  my $name = shift;
  my $self = {};
  $self->{'name'} = $name;
  bless $self,$class;
  $self->standard_initialisation();
  return $self;
}

sub kind { return 'MONITOR'; }

package OpcConfig::TemplateGroup;

sub new {
  my $class = shift;
  my $name = shift;
  my $self = {};
  $self->{'name'} = $name;
  bless $self,$class;
  $self->standard_initialisation();
  return $self;
}

sub kind { return 'TEMPLATE_GROUP'; }

package OpcConfig::ECSTemplate;

#use base 'OpcConfig::Template';
# Not sure about this one

sub new {
  my $class = shift;
  my $name = shift;
  my $self = {};
  $self->{'name'} = $name;
  bless $self,$class;
}

sub kind { return 'ECS'; }

package OpcConfig::ScheduleTemplate;

use base 'OpcConfig::Template';

sub new {
  my $class = shift;
  my $name = shift;
  my $self = {};
  $self->{'name'} = $name;
  bless $self,$class;
  $self->standard_initialisation();
  return $self;
}

sub kind { return 'SCHEDULE'; }

package OpcConfig::SnmpTrapTemplate;

use base 'OpcConfig::Template';

sub new {
  my $class = shift;
  my $name = shift;
  my $self = {};
  $self->{'name'} = $name;
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


package OpcConfig;

sub make_template {
  my $name = shift;
  my $type = shift;
  return new OpcConfig::OpcmsgTemplate($name) if $type eq 'OPCMSG';
  return new OpcConfig::LogfileTemplate($name) if $type eq 'LOGFILE';
  return new OpcConfig::MonitorTemplate($name) if $type eq 'MONITOR';
  return new OpcConfig::TemplateGroup($name) if $type eq 'TEMPLATE_GROUP';
  return new OpcConfig::ECSTemplate($name) if $type eq 'ECS';
  return new OpcConfig::ScheduleTemplate($name) if $type eq 'SCHEDULE';
  return new OpcConfig::SnmpTrapTemplate($name) if $type eq 'SNMP';
  die "Unknown template type $type";
}



1;
