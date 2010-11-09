package TrapdConfig;

package TrapdConfig::Action;

sub new {
  my $class = shift;
  my $self = {};
  my $line = shift;
  bless $self;
  $self->{"doing"} = undef;
  if ($line =~ /^ACTION\s*(\d+)\s*"(.*)"\s*(.*)$/) {
    $self->{"position"} = $1;
    $self->{"description"} = $2;
    $self->{"command"} = $3;
  } else {
    die "Could understand the line $line";
  }
  return $self;
}

sub extra_line {
  my $self = shift;
  my $line = shift;
  if ($line =~ /^SDESC\s*$/) { 
    $self->{"doing"} = "long description";
    $self->{"long description"} = "";
    return; 
  }
  if ($line =~ /^EDESC\s*$/) { $self->{"doing"} = undef; return; }

  die "Could not understand $line" unless defined $self->{"doing"};

  $self->{$self->{"doing"}} .= $line;
}

package TrapdConfig::Event;

sub new {
  my $class = shift;
  my $line = shift;
  my $self = {};
  bless $self;
  if ($line =~ /^EVENT\s*(\w+)\s*([.0-9*]+)\s*"(.*)"\s*(\w+)\s*/) {
    $self->{"name"} = $1;
    $self->{"oid"} = $2;
    $self->{"category"} = $3;
    $self->{"severity"} = $4;
    $self->{"doing"} = undef;
    $self->{"popup"} = undef;
    $self->{"forwarding"} = undef;
    $self->{"execute"} = undef;
  } else {
    chomp $line;
    die "Could not understand $line";
  }
  return $self;
}

sub extra_line {
  my $self = shift;
  my $line = shift;
  if ($line =~ /^FORMAT\s*(.*)$/) {
    $self->{"format"} = $1;
    $self->{"doing"} = undef;
    return;
  }
  if ($line =~ /^DISPLAY\s*(.*)$/ ) {
    $self->{"popup"} = $1;
    $self->{"doing"} = undef;
    return;
  }
  if ($line =~ /^FORWARD\s*(.*)$/ ) {
    $self->{"forwarding"} = $1;
    $self->{"doing"} = undef;
    return;
  }
  if ($line =~ /^EXEC\s*(.*)$/ ) {
    $self->{"execute"} = $1;
    $self->{"doing"} = undef;
    return;
  }

  if ($line =~ /^SDESC\s*$/) { 
    $self->{"doing"} = "long description";
    $self->{"long description"} = "";
    return; 
  }
  if ($line =~ /^EDESC\s*$/) { $self->{"doing"} = undef; return; }

  die "Could not understand $line in format ".($self->name()) unless defined $self->{"doing"};

  $self->{$self->{"doing"}} .= $line;
}

sub name {  my $self = shift;  return $self->{"name"}; }
sub oid {  my $self = shift;  return $self->{"oid"}; }
sub description {  my $self = shift;  return $self->{"long description"}; }
sub severity { 
  my $self = shift;
  return "Suppress" if $self->{"category"} =~ /LOGONLY/;
  return $self->{"severity"};
}
sub category { my $self = shift; return $self->{"category"}; }
sub forwarding { my $self = shift; return $self->{"forwarding"}; }
sub alarm_format { my $self = shift; return $self->{"format"}; }

package TrapdConfig;

use strict;

sub new {
  my $class = shift;
  my $filename = shift;
  my $self = {};
  my $currently_doing = undef;
  $self->{"category"} = {};
  $self->{"actions"} = [];
  $self->{"oidaliases"} = {};
  $self->{"events_by_name"} = {};
  $self->{"events_by_oid"} = {};
  bless $self;
  open(FILE,$filename) || die "Can't read $filename";
  while (<FILE>) {
    next if /^#/;
    if (/^VERSION\s*(\d+)\s*$/) { 
      $self->{"version"} = $1; 
      $currently_doing = undef;
      next; 
    }
    if (/^CATEGORY\s*(\d+)\s*"([^"]*)".*/) {
      $self->{"category"}->{$1} = $2;
      $currently_doing = undef;
      next;
    }
    if (/^ACTION/) { 
      $currently_doing = new TrapdConfig::Action($_);
      push(@{$self->{"actions"}},$currently_doing);
      next; 
    }
    if (/^OID_ALIAS\s*(\w*)\s*([.0-9]+)$/) {
      $self->{"oidaliases"}->{$1} = $2;
      $currently_doing = undef;
      next;
    }
    if (/^EVENT/) {
      $currently_doing = new TrapdConfig::Event($_);
      $self->{"events_by_oid"}->{$currently_doing->oid()} = $currently_doing;
      $self->{"events_by_name"}->{$currently_doing->name()} = $currently_doing;
      next;
    }
    die "Cannot understand \"$_\"" unless defined $currently_doing;
    $currently_doing->extra_line($_);
  }
  close(FILE);
  return $self;
}

sub all_event_oids {
  my $self = shift;
  return keys %{$self->{"events_by_oid"}};
}

sub event_by_oid {
  my $self = shift;
  my $oid = shift;
  return $self->{"events_by_oid"}->{$oid};
}

sub best_enterprise {
  my $self = shift;
  my $oid = shift;
  my $oid_alias_name;
  my $length;
  my $oid_alias;
  my $shortened_oid;
  my $best_length = 0;
  my $best_enterprise = undef;
  foreach $oid_alias_name (keys %{$self->{"oidaliases"}}) {
    $oid_alias = $self->{"oidaliases"}->{$oid_alias_name};
    $length = length($oid_alias);
    $shortened_oid = substr($oid,0,$length+1);
    if ($shortened_oid eq "$oid_alias.") {
      if ($length > $best_length) { 
	$best_enterprise = $oid_alias_name;
	$best_length = $length;
      }
    }
  }
  return $best_enterprise if defined $best_enterprise;
  return "";
}

1;

