#!/usr/bin/perl
use strict;
use warnings;
use CGI::Carp qw(fatalsToBrowser);
use CGI qw/:standard/;
use Scalar::Util qw(looks_like_number);
# use Switch;
# use AptPkg::Config;
use LoxBerry::System;

my $bins = LoxBerry::System::get_binaries();
# print STDERR "Das Binary zu Grep ist $bins->{GREP}.";
# system("$bins->{ZIP} myarchive.zip *");

print header;

my $action = param('action');
my $value = param('value');

print STDERR "Action: $action // Value: $value\n";

if    ($action eq 'secupdates') { &secupdates; }
elsif ($action eq 'secupdates-autoreboot') { &secupdatesautoreboot; }
elsif ($action eq 'poweroff') { &poweroff; }
elsif ($action eq 'reboot') { &reboot; }
elsif ($action eq 'lbupdate-reltype') { &lbupdate; }
elsif ($action eq 'lbupdate-installtype') { &lbupdate; }
elsif ($action eq 'lbupdate-installtime') { &lbupdate; }
elsif ($action eq 'lbupdate-runcheck') { &lbupdate; }
elsif ($action eq 'lbupdate-runinstall') { &lbupdate; }
elsif ($action eq 'testenvironment') { &testenvironment; }
elsif ($action eq 'changelanguage') { change_generalcfg("BASE.LANG", $value);}
else   { print "<red>Action not supported.</red>"; }

################################
# unattended-upgrades setting
################################
sub secupdates
{
	print STDERR "ajax-config-handler: ajax secupdates\n";
	print STDERR "Value is: $value\n";
	
	if (!looks_like_number($value) && $value ne 'query') 
		{ print "<red>Value not supported.</red>"; 
		  return();}
	
	my $aptfile = "/etc/apt/apt.conf.d/02periodic";
	open(FILE, $aptfile) || die "File not found";
	my @lines = <FILE>;
	close(FILE);

	my $querystring;
	my $queryresult;
	
	my @newlines;
	foreach(@lines) {
		if (begins_with($_, "APT::Periodic::Unattended-Upgrade"))
			{   # print STDERR "############ FOUND #############";
				if ($value eq 'query') {
					my ($querystring, $queryresult) = split / /;
					print STDERR "### QUERY result: " . $queryresult . "\n";
					$queryresult =~ s/[\$"#@~!&*()\[\];.,:?^ `\\\/]+//g;
					print "option-secupdates-" . $queryresult;
				} else {
					$_ = "APT::Periodic::Unattended-Upgrade \"$value\";\n"; }
			}
		if (begins_with($_, "APT::Periodic::Update-Package-Lists") && $value ne 'query')
			{   # print STDERR "############ FOUND #############";
				$_ = "APT::Periodic::Update-Package-Lists \"$value\";\n";
			}
		push(@newlines,$_);
	}

	if ($value ne 'query') {
		open(FILE, '>', $aptfile) || die "File not found";
		print FILE @newlines;
		close(FILE);
	}
}

############################################
# unattended-upgrades auto-reboot setting
############################################
sub secupdatesautoreboot
{
	print STDERR "ajax-config-handler: secupdates-autoreboot\n";
	print STDERR "Value is: $value\n";
	
	if ($value ne "true" && $value ne "false" && $value ne "query") 
		{ print "<red>Value not supported.</red>"; 
		  return();}
	
	my $aptfile = "/etc/apt/apt.conf.d/50unattended-upgrades";
	open(FILE, $aptfile) || die "File not found";
	my @lines = <FILE>;
	close(FILE);

	my $querystring;
	my $queryresult;
	
	my @newlines;
	foreach(@lines) {
		if (begins_with($_, "Unattended-Upgrade::Automatic-Reboot-WithUsers"))
			{   # print STDERR "############ FOUND #############";
				if ($value eq 'query') {
					my ($querystring, $queryresult) = split / /;
					# print STDERR "### QUERY result: " . $queryresult . "\n";
					$queryresult =~ s/[\$"#@~!&*()\[\];.,:?^ `\\\/]+//g; #" Syntax highlighting fix for UltraEdit
					print "secupdates-autoreboot-" . $queryresult;
				} else {
					$_ = $value eq "false" ? "Unattended-Upgrade::Automatic-Reboot-WithUsers \"false\";\n" : "Unattended-Upgrade::Automatic-Reboot-WithUsers \"true\";\n";}
			}
		push(@newlines,$_);
	}

	if ($value ne 'query') {
		open(FILE, '>', $aptfile) || die "File not found";
		print FILE @newlines;
		close(FILE);
	}
}

############################################
# lbupdate
############################################
sub lbupdate
{
	print STDERR "ajax-config-handler: lbupdate\n";

	if ($action eq 'lbupdate-runcheck') {
		my $output = qx { sudo $lbhomedir/sbin/loxberryupdatecheck.pl output=json };
		print $output;
		exit(0);
		
	}
	
	if ($action eq 'lbupdate-runinstall') {
		my $output = qx {sudo $lbhomedir/sbin/loxberryupdatecheck.pl output=json update=1};
		print $output;
		exit(0);
	}
	
	
	if ($action eq 'lbupdate-reltype') {
		if ($value eq 'release' || $value eq 'prerelease' || $value eq 'latest') { 
			change_generalcfg('UPDATE.RELEASETYPE', $value);
		}
	return;
	}

	if ($action eq 'lbupdate-installtype') {
		unlink "$lbhomedir/system/cron/cron.daily/loxberryupdate_cron" if (-e "$lbhomedir/system/cron/cron.daily/loxberryupdate_cron");
		unlink "$lbhomedir/system/cron/cron.weekly/loxberryupdate_cron" if (-e "$lbhomedir/system/cron/cron.weekly/loxberryupdate_cron");
		unlink "$lbhomedir/system/cron/cron.monthly/loxberryupdate_cron" if (-e "$lbhomedir/system/cron/cron.monthly/loxberryupdate_cron");
		if ($value eq 'notify' || $value eq 'install') {
			if (param('installtime') eq '1') {
				symlink "$lbssbindir/loxberryupdate_cron.sh", "$lbhomedir/system/cron/cron.daily/loxberryupdate_cron" or print STDERR "Error linking $lbhomedir/system/cron/cron.daily/loxberryupdate_cron";
			} elsif (param('installtime') eq '7') {
				symlink "$lbssbindir/loxberryupdate_cron.sh", "$lbhomedir/system/cron/cron.weekly/loxberryupdate_cron" or print STDERR "Error linking $lbhomedir/system/cron/cron.weekly/loxberryupdate_cron";
			} elsif (param('installtime') eq '30') {
				symlink "$lbssbindir/loxberryupdate_cron.sh", "$lbhomedir/system/cron/cron.monthly/loxberryupdate_cron" or print STDERR "Error linking $lbhomedir/system/cron/cron.monthly/loxberryupdate_cron";
			}
		}
		if ($value eq 'disabled' || $value eq 'notify' || $value eq 'install') { 
			change_generalcfg('UPDATE.INSTALLTYPE', $value);
		}
	return;
	}

	if ($action eq 'lbupdate-installtime') { 
		unlink "$lbhomedir/system/cron/cron.daily/loxberryupdate_cron" if (-e "$lbhomedir/system/cron/cron.daily/loxberryupdate_cron");
		unlink "$lbhomedir/system/cron/cron.weekly/loxberryupdate_cron" if (-e "$lbhomedir/system/cron/cron.weekly/loxberryupdate_cron");
		unlink "$lbhomedir/system/cron/cron.monthly/loxberryupdate_cron" if (-e "$lbhomedir/system/cron/cron.monthly/loxberryupdate_cron");
		if (($value eq '1' || $value eq '7' || $value eq '30') && (param('installtype') eq 'install' || param('installtype') eq 'notify')) {	
			if ($value eq '1') {
				symlink "$lbssbindir/loxberryupdate_cron.sh", "$lbhomedir/system/cron/cron.daily/loxberryupdate_cron" or print STDERR "Error linking $lbhomedir/system/cron/cron.daily/loxberryupdate_cron";
			} elsif ($value eq '7') {
				symlink "$lbssbindir/loxberryupdate_cron.sh", "$lbhomedir/system/cron/cron.weekly/loxberryupdate_cron" or print STDERR "Error linking $lbhomedir/system/cron/cron.weekly/loxberryupdate_cron";
			} elsif ($value eq '30') {
				symlink "$lbssbindir/loxberryupdate_cron.sh", "$lbhomedir/system/cron/cron.monthly/loxberryupdate_cron" or print STDERR "Error linking $lbhomedir/system/cron/cron.monthly/loxberryupdate_cron";
			}
			change_generalcfg('UPDATE.INTERVAL', $value);
		}
	return;
	}
}

############################################
# poweroff
############################################
sub poweroff
{
	print STDERR "ajax-config-handler: ajax poweroff - Forking poweroff\n";
	# LOGINF "Forking poweroff ...";
	my $pid = fork();
	if (not defined $pid) {
		print STDERR "ajax-config-handler: Cannot fork poweroff.";
		# LOGCRIT "Cannot fork poweroff.";
	} 
	if (not $pid) {	
		# LOGINF "Executing poweroff forked...";
		print STDERR "Executing poweroff forked...";
		
		exec("$lbhomedir/sbin/sleeper.sh sudo $bins->{POWEROFF} </dev/null >/dev/null 2>&1 &");
		exit(0);
	}
	exit(0);
}

############################################
# reboot
############################################
sub reboot
{
	print STDERR "ajax-config-handler: ajax reboot\n";
	# LOGINF "Forking reboot ...";
	my $pid = fork();
	if (not defined $pid) {
		# LOGCRIT "Cannot fork reboot.";
		print STDERR "Cannot fork reboot.";
	}
	if (not $pid) {
		# LOGINF "Executing reboot forked...";
		print STDERR "Executing reboot forked...";
		exec("$lbhomedir/sbin/sleeper.sh sudo $bins->{REBOOT} </dev/null >/dev/null 2>&1 &");
		exit(0);
	}
	exit(0);
}

###################################################################
# change general.cfg
###################################################################
sub change_generalcfg
{
	my ($key, $val) = @_;
	if (!$key) {
		return undef;
	}
	my $cfg = new Config::Simple("$lbsconfigdir/general.cfg") or return undef;

	if (!$val) {
		# Delete key
		$cfg->delete($key);
	} else {
		$cfg->param($key, $val);
	}
	$cfg->write() or return undef;
	return 1;
}

sub testenvironment
{
print "<h2>TEST 1 with system()</h2>";
print "ajax-config-handler: TESTENVIRONMENT (lbhomedir is $lbhomedir)<br>";
system("sudo $lbhomedir/sbin/testenvironment.pl");
print "ajax-config-handler: Finished.<br>";

print "<h2>TEST 2 with qx{}</h2>";
print "ajax-config-handler: TESTENVIRONMENT (lbhomedir is $lbhomedir)<br>";
my $output = qx{sudo $lbhomedir/sbin/testenvironment.pl};
print $output;
print "ajax-config-handler: Finished.<br>";

}
