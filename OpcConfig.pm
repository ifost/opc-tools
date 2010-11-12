package OpcConfig;

=head1 OpcConfig

This module can read the dumps you get out of OpC / Operations Manager /
VantagePoint Operations / Operations Manager for Unix when you run
C<opccfgdwn>.

=cut

use strict;

my $version = '$Id: OpcConfig.pm 1467 2010-09-24 01:40:02Z gregb $';

sub version { return $version; }

=head2 new()

Constructor for a new template. Doesn't require arguments.

=cut

sub new {
  my $class = shift;
  my $self = {};
  bless $self;
}


=head2 $objconfig_obj->make_template($name,$type)

C<$name> is just the name of the template.

C<$type> can be one of:

=over

=item OPCMSG

=item LOGFILE

=item MONITOR

=item TEMPLATE_GROUP

=item ECS

=item SCHEDULE

=item SNMP

=back

=cut

use OpcConfig::Template;

sub make_template {
  my $self = shift;
  my $name = shift;
  my $type = shift;
  return new OpcConfig::Template::OpcmsgTemplate($name,$self) if $type eq 'OPCMSG';
  return new OpcConfig::Template::LogfileTemplate($name,$self) if $type eq 'LOGFILE';
  return new OpcConfig::Template::MonitorTemplate($name,$self) if $type eq 'MONITOR';
  return new OpcConfig::Template::TemplateGroup($name,$self) if $type eq 'TEMPLATE_GROUP';
  return new OpcConfig::Template::ECSTemplate($name,$self) if $type eq 'ECS';
  return new OpcConfig::Template::ScheduleTemplate($name,$self) if $type eq 'SCHEDULE';
  return new OpcConfig::Template::SnmpTrapTemplate($name,$self) if $type eq 'SNMP';
  die "Unknown template type $type";
}


=head2 $opcconfig_obj->read_dir($dirname)

Reads through all .dat files below the directory name, skipping .svn directories.

=cut

sub read_dir {
  my $self = shift;
  my $dirname = shift;
  if (-f $dirname and $dirname =~ /\.dat$/) {
    #print STDERR "$dirname\n";
    $self->read_file($dirname);
    return;
  }
  if (-f $dirname) { return; }
  my $dirhandle;
  opendir($dirhandle,$dirname) || die "Can't read $dirname";
  my @entries = readdir($dirhandle);
  closedir($dirhandle);
  my $dir;
  foreach $dir (@entries) {
    next if $dir =~ /^\.$/;
    next if $dir =~ /^\.\.$/;
    next if $dir =~ /^\.svn$/;
    $self->read_dir($dirname."/".$dir);
  }
}


=head2 line_complete($line)

Does this line have an odd number of non-backslashed " characters in it?

=cut

sub line_complete {
  my $line = shift;
  $line =~ s/\\\\//g; # Get rid of \\, because they are requesting an ordinary character
  $line =~ s/\\"//g; # Get rid of \", because they are ordinary characters
  $line =~ tr/"//cd; # Get rid of everything but "
  return length($line) % 2 == 0;
}

=head2 $opcconfig_obj->read_file($filename)

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

    if (!line_complete($workspace)) {
      $pre_workspace = $workspace;
      $workspace_is_continued = 1;
      next;
    }
    #print STDERR "Continued workspace $workspace\n\n" if $workspace_is_continued and $workspace !~ /HELPTEXT/;
    $workspace_is_continued = 0;

    next if $workspace =~ /SYNTAX_VERSION/;
    if ($workspace =~ /^\s*(OPCMSG|LOGFILE|MONITOR|TEMPLATE_GROUP|ECS|SCHEDULE|SNMP)\s*"(.*)"/) {
      my $template_type = $1;
      my $template_name = $2;
      $self->{$template_type} = {} unless exists $self->{$template_type};
      $current_template = $self->make_template($template_name,$template_type);
      $current_condition = undef;
      $self->{$template_type}->{$template_name} = $current_template;
      $have_started_on_conditions = 0;
      next;
    }

    if ($workspace =~ /^\s*MEMBER_(\w*)\s*"(.*)"/) {
      $current_template->store("MEMBER_$1",$2);
      next;
    }

    if ($workspace =~ /^\s*(SUPP_UNM_CONDITIONS|SUPPRESSCONDITIONS|MSGCONDITIONS)/) {
      my $condition_type = $1;
      $current_template->next_condition_type($condition_type);
      $have_started_on_conditions = 1;
      next;
    }
    if ($workspace =~ /(SUPP_UNM_CONDITIONS|SUPPRESSCONDITIONS|MSGCONDITIONS)/) {
      die "Error handling workspace $workspace at $.";
    }

    if ($workspace =~ /^\s*DESCRIPTION\s*"(.*)"\s*$/s) {
      if ($have_started_on_conditions) {
	$current_condition = $current_template->add_condition($1);
      } else {
	# Must be the description of the template
	$current_template->set_description($1);
      }
      next;
    }
    #die "Problem handling workspace $workspace " if ($workspace =~ /DESCRIPTION/);

    if (!defined $current_condition and $workspace =~ /^\s*SET\s*$/) {
      # Must be a schedule template
      $current_template->start_reading_generated_message_attributes();
      next;
    }

    #if ($workspace =~ /CONDITION_ID/) { print STDERR " --> $workspace\n"; }

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
	$current_template->store($keyword,$answer);
      }
     #die "$workspace" if $answer =~ /"/ and not $answer =~ /".*"/;
    }
  }
}


=head2 $opcconfig_obj->print_brief_list()

Just for debugging -- prints out to STDOUT all template types and names.

=cut


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


=head2 $opcconfig_obj->get_template($template_type,$template_name)

Returns one template.

=cut

sub get_template {
  my $self = shift;
  my $template_type = shift;
  my $template_name = shift;
  return $self->{$template_type}->{$template_name};
}



=head2 show_differences()

This function probably doesn't work.

=cut


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



1;
