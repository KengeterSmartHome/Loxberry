#!/usr/bin/perl

# Input parameters from loxberryupdate.pl:
# 	release: the final version update is going to (not the version of the script)
#   logfilename: The filename of LoxBerry::Log where the script can append
#   updatedir: The directory where the update resides
#   cron: If 1, the update was triggered automatically by cron

use LoxBerry::Update;

init();

#
# Switching to rwth-aachen.de for the Rasbian Repo due to lot of connection errors with original rpo
#
LOGINF "Replacing archive.raspbian.org with ftp.halifax.rwth-aachen.de/raspbian in /etc/apt/sources.list.";
system ("/bin/sed -i 's:mirrordirector.raspbian.org:ftp.halifax.rwth-aachen.de/raspbian:g' /etc/apt/sources.list");
system ("/bin/sed -i 's:archive.raspbian.org:ftp.halifax.rwth-aachen.de/raspbian:g' /etc/apt/sources.list");
unlink ("/etc/apt/sources.list.d/raspi.list");

LOGINF "Getting signature for ftp.halifax.rwth-aachen.de/raspbian/raspbian.";
$output = qx ( wget http://ftp.halifax.rwth-aachen.de/raspbian/raspbian.public.key -O - | apt-key add - );
$exitcode  = $? >> 8;
if ($exitcode != 0) {
	LOGERR "Error getting signature for ftp.halifax.rwth-aachen.de/raspbian - Error $exitcode";
	LOGDEB $output;
	$errors++;
} else {
     	LOGOK "Got signature for ftp.halifax.rwth-aachen.de/raspbian successfully.";
}

#
# Installing new network templates
#
LOGINF "Installing new network templates for IPv6...";
unlink "$lbhomedir/system/network/interfaces.eth_dhcp";
unlink "$lbhomedir/system/network/interfaces.eth_static";
unlink "$lbhomedir/system/network/interfaces.wlan_dhcp";
unlink "$lbhomedir/system/network/interfaces.wlan_static";
copy_to_loxberry("/system/network/interfaces.loopback");
copy_to_loxberry("/system/network/interfaces.ipv4");
copy_to_loxberry("/system/network/interfaces.ipv6");

LOGINF "Installing additional Perl modules...";
apt_update("update");
apt_install("libdata-validate-ip-perl");

#
# Upgrade Raspbian on next reboot
#
LOGINF "Upgrading system to latest Raspbian release ON NEXT REBOOT.";
my $logfilename_wo_ext = $logfilename;
$logfilename_wo_ext =~ s{\.[^.]+$}{};
open(F,">$lbhomedir/system/daemons/system/99-updaterebootv200");
print F <<EOF;
#!/bin/bash
perl $lbhomedir/sbin/loxberryupdate/updatereboot_v2.0.0.pl logfilename=$logfilename_wo_ext-reboot 2>&1
EOF
close (F);
qx { chmod +x $lbhomedir/system/daemons/system/99-updaterebootv200 };

#
# Disable Apache2 for next reboot
#
LOGINF "Disabling Apache2 Service for next reboot...";
my $output = qx { systemctl disable apache2.service };
$exitcode = $? >> 8;
if ($exitcode != 0) {
	LOGWARN "Could not disable Apache webserver - Error $exitcode";
	LOGWARN "Maybe your LoxBerry does not respond during system upgrade after reboot. Please be patient when rebooting!";
} else {
	LOGOK "Apache Service disabled successfully.";
}

LOGINF "Installing Node.js V12...";

LOGINF "Adding Node.js repository key to LoxBerry keyring...";
my $output = qx { curl -s https://deb.nodesource.com/gpgkey/nodesource.gpg.key | apt-key add - };
my $exitcode  = $? >> 8;
if ($exitcode != 0) {
		LOGERR "Error adding Node.js repo key to LoxBerry - Error $exitcode";
		LOGDEB $output;
	        $errors++;
	} else {
        	LOGOK "Node.js repo key added successfully.";
	}
LOGINF "Adding Yarn repository key to LoxBerry keyring...";
my $output = qx { curl -sL https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add - };
my $exitcode  = $? >> 8;
if ($exitcode != 0) {
		LOGERR "Error adding Yarn repo key to LoxBerry - Error $exitcode";
		LOGDEB $output;
	        $errors++;
	} else {
        	LOGOK "Yarn repo key added successfully.";
	}

LOGINF "Adding Node.js V12.x repository to LoxBerry...";
qx { echo 'deb https://deb.nodesource.com/node_12.x buster main' > /etc/apt/sources.list.d/nodesource.list };
qx { echo 'deb-src https://deb.nodesource.com/node_12.x buster main' >> /etc/apt/sources.list.d/nodesource.list };

if ( ! -e '/etc/apt/sources.list.d/nodesource.list' ) {
	LOGERR "Error adding Node.js repo to LoxBerry - Repo file missing";
        $errors++;
} else {
	LOGOK "Node.js repo added successfully.";
}

unlink("/etc/apt/sources.list.d/yarn.list");
LOGINF "Adding Yarn repository to LoxBerry...";
my $output = qx { echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list };
my $exitcode  = $? >> 8;
if ($exitcode != 0) {
	LOGERR "Error adding Yarn repo to LoxBerry - Error $exitcode";
	LOGDEB $output;
        $errors++;
} else {
	LOGOK "Yarn repo added successfully.";
}

LOGINF "Update apt Database";
apt_update("update");

LOGINF "Installing Node.js and Yarn packages...";
apt_install("nodejs yarn");

LOGINF "Testing Node.js...";
LOGDEB `node -e "console.log('Hello LoxBerry users, this is Node.js '+process.version);"`;

LOGINF "Installing additional Perl modules...";
apt_install("libdata-validate-ip-perl");

LOGINF "Removing obsolete ssmtp package...";
apt_remove("ssmtp bsd-mailx");

LOGINF "Installing msmtp package and replacing ssmtp...";
copy_to_loxberry("/system/msmtp", "loxberry");
apt_install("msmtp msmtp-mta bsd-mailx");

#
# Migrating ssmtp config to msmtp
#
if (-e "$lbhomedir/system/ssmtp/ssmtp.conf" ) {

	my $mailfile = $lbsconfigdir . "/mail.json";
	my $msmtprcfile = $lbhomedir . "/system/msmtp/msmtprc";
	
	$mailobj = LoxBerry::JSON->new();
	$mcfg = $mailobj->open(filename => $mailfile);
	
	if ( is_enabled ($mcfg->{SMTP}->{ACTIVATE_MAIL}) ) {
		LOGINF "Migrating ssmtp configuration to msmtp...";
		my $error;
		# Config
		open(F,">$msmtprcfile") || $error++;
		flock(F,2);
		print F "aliases $lbhomedir/system/msmtp/aliases\n";
		print F "logfile $lbhomedir/log/system_tmpfs/mail.log\n";
		print F "from $mcfg->{SMTP}->{EMAIL}\n";
		print F "host $mcfg->{SMTP}->{SMTPSERVER}\n";
		print F "port $mcfg->{SMTP}->{PORT}\n";
		if ( is_enabled($mcfg->{SMTP}->{AUTH}) ) {
			print F "auth on\n";
			print F "user $mcfg->{SMTP}->{SMTPUSER}\n";
			print F "password $mcfg->{SMTP}->{SMTPPASS}\n";
		} else {
			print F "auth off\n";
		}
		if ( is_enabled($mcfg->{SMTP}->{CRYPT}) ) {
			print F "tls on\n";
			print F "tls_trust_file /etc/ssl/certs/ca-certificates.crt\n"
		} else {
			print F "tls off\n";
		}
		flock(F,8);
		close(F);
		$output = qx { chmod 0600 $msmtprcfile 2>&1 };
		$exitcode  = $? >> 8;
		if ($exitcode != 0) {
		        LOGERR "Error setting 0600 file permissions for $msmtprcfile - Error $exitcode";
			$error++;
		} else {
			LOGOK "Changing file permissions successfully for $msmtprcfile";
		}
		$output = qx { chown loxberry:loxberry $msmtprcfile 2>&1 };
		$exitcode  = $? >> 8;
		if ($exitcode != 0) {
		        LOGERR "Error changing owner to loxberry for $msmtprcfile - Error $exitcode";
			$error++;
		} else {
			LOGOK "Changing owner to loxberry successfully for $msmtprcfile";
		}
		# Aliases
		open(F,">$lbhomedir/system/msmtp/aliases");
		flock(F,2);
		print F "root: $mcfg->{SMTP}->{EMAIL}\n";
		print F "loxberry: $mcfg->{SMTP}->{EMAIL}\n";
		print F "default: $mcfg->{SMTP}->{EMAIL}\n";
		flock(F,8);
		close(F);
		$output = qx { chmod 0600 $lbhomedir/system/msmtp/aliases 2>&1 };
		$exitcode  = $? >> 8;
		if ($exitcode != 0) {
		        LOGERR "Error setting 0600 file permissions for $lbhomedir/system/msmtp/aliases - Error $exitcode";
			$error++;
		} else {
			LOGOK "Changing file permissions successfully for $lbhomedir/system/msmtp/aliases";
		}
		$output = qx { chown loxberry:loxberry $lbhomedir/system/msmtp/aliases 2>&1 };
		$exitcode  = $? >> 8;
		if ($exitcode != 0) {
		        LOGERR "Error changing owner to loxberry for $lbhomedir/system/msmtp/aliases - Error $exitcode";
			$error++;
		} else {
			LOGOK "Changing owner to loxberry successfully for $lbhomedir/system/msmtp/aliases";
		}
		if ($error) {
			LOGWARN "Could not migrate config file from ssmtp to msmtp. Please configure the Mailserver Widget manually!";
			unlink "$lbhomedir/system/msmtp/aliases";
			unlink "$msmtprcfile";
		} else {
			LOGOK "Created new msmtp config successfully.";
			my $email = $mcfg->{SMTP}->{EMAIL};
			LOGINF "Cleaning mail.json due to previously saved credentials in that config file";
			delete $mcfg->{SMTP};
			$mcfg->{SMTP}->{ACTIVATE_MAIL} = "1";
			$mcfg->{SMTP}->{ISCONFIGURED} = "1";
			$mcfg->{SMTP}->{EMAIL} = "$email";
			$mailobj->write();
			LOGINF "Activating new msmtp configuration...";
			system( "ln -s $lbhomedir/system/msmtp/msmtprc $lbhomedir/.msmtprc" );
		}

	}

}	

LOGINF "Removing old ssmtp configuration...";
delete_directory ("$lbhomedir/system/ssmtp");

LOGINF "Replacing auto.smb with LoxBerry's modified auto.smb ...";
copy_to_loxberry("/system/autofs", "root");
if ( ! -l '/etc/auto.smb' ) {
	# Not a symlink
	execute ( command => 'mv -f /etc/auto.smb /etc/auto.smb.backup', log => $log );
}

if ( ! -e "$lbhomedir/system/autofs" ) {
	mkdir "$lbhomedir/system/autofs" or do { LOGERR "Could not create dir $lbhomedir/system/autofs"; $errors++; };
}
unlink "/etc/auto.smb";
symlink "$lbhomedir/system/autofs/auto.smb", "/etc/auto.smb" or do { LOGERR "Could not create symlink from /etc/auto.smb to $lbhomedir/system/autofs/auto.smb"; $errors++; };
execute ( command => "chmod 0755 $lbhomedir/system/autofs/auto.smb", log => $log );
execute ( command => "systemctl restart autofs", log => $log );

LOGINF "Updating PHP 7.x configuration";
LOGINF "Deleting ~/system/php...";
delete_directory("$lbhomedir/system/php");
LOGINF "Re-creating directory ~/system/php...";
mkdir "$lbhomedir/system/php" or do { LOGERR "Could not create dir $lbhomedir/system/php"; $errors++; };
LOGINF "Copying LoxBerry PHP config...";
copy_to_loxberry("/system/php/loxberry-apache.ini");
copy_to_loxberry("/system/php/loxberry-cli.ini");

LOGINF "Deleting old LoxBerry PHP config...";
my @phpfiles = ( 
	'/etc/php/7.0/apache2/conf.d/20-loxberry.ini', 
	'/etc/php/7.0/cgi/conf.d/20-loxberry.ini', 
	'/etc/php/7.0/cli/conf.d/20-loxberry.ini', 
	'/etc/php/7.1/apache2/conf.d/20-loxberry.ini', 
	'/etc/php/7.1/cgi/conf.d/20-loxberry.ini', 
	'/etc/php/7.1/cli/conf.d/20-loxberry.ini', 
	'/etc/php/7.2/apache2/conf.d/20-loxberry.ini', 
	'/etc/php/7.2/cgi/conf.d/20-loxberry.ini', 
	'/etc/php/7.2/cli/conf.d/20-loxberry.ini', 
	'/etc/php/7.3/apache2/conf.d/20-loxberry.ini', 
	'/etc/php/7.3/cgi/conf.d/20-loxberry.ini', 
	'/etc/php/7.3/cli/conf.d/20-loxberry.ini', 
);
foreach (@phpfiles) {
	if (-e "$_") { 
		unlink "$_" or do { LOGERR "Could not delete $_"; $errors++; }; 
	}
}

LOGINF "Creating symlinks to new configuration....";

if ( -e "/etc/php/7.0" ) {
	my $output = qx { ln -vsfn $lbhomedir/system/php/loxberry-apache.ini /etc/php/7.0/apache2/conf.d/20-loxberry-apache.ini >> $logfilename 2>&1 };
	my $output = qx { ln -vsfn $lbhomedir/system/php/loxberry-apache.ini /etc/php/7.0/cgi/conf.d/20-loxberry-apache.ini >> $logfilename 2>&1};
	my $output = qx { ln -vsfn $lbhomedir/system/php/loxberry-cli.ini /etc/php/7.0/cli/conf.d/20-loxberry-cli.ini >> $logfilename 2>&1};
};
if ( -e "/etc/php/7.1" ) {
	my $output = qx { ln -vsfn $lbhomedir/system/php/loxberry-apache.ini /etc/php/7.1/apache2/conf.d/20-loxberry-apache.ini >> $logfilename 2>&1};
	my $output = qx { ln -vsfn $lbhomedir/system/php/loxberry-apache.ini /etc/php/7.1/cgi/conf.d/20-loxberry-apache.ini >> $logfilename 2>&1};
	my $output = qx { ln -vsfn $lbhomedir/system/php/loxberry-cli.ini /etc/php/7.1/cli/conf.d/20-loxberry-cli.ini >> $logfilename 2>&1};
};
if ( -e "/etc/php/7.2" ) {
	my $output = qx { ln -vsfn $lbhomedir/system/php/loxberry-apache.ini /etc/php/7.2/apache2/conf.d/20-loxberry-apache.ini >> $logfilename 2>&1 };
	my $output = qx { ln -vsfn $lbhomedir/system/php/loxberry-apache.ini /etc/php/7.2/cgi/conf.d/20-loxberry-apache.ini >> $logfilename 2>&1 };
	my $output = qx { ln -vsfn $lbhomedir/system/php/loxberry-cli.ini /etc/php/7.2/cli/conf.d/20-loxberry-cli.ini >> $logfilename 2>&1 };
};
if ( -e "/etc/php/7.3" ) {
	my $output = qx { ln -vsfn $lbhomedir/system/php/loxberry-apache.ini /etc/php/7.3/apache2/conf.d/20-loxberry-apache.ini >> $logfilename 2>&1 };
	my $output = qx { ln -vsfn $lbhomedir/system/php/loxberry-apache.ini /etc/php/7.3/cgi/conf.d/20-loxberry-apache.ini >> $logfilename 2>&1 };
	my $output = qx { ln -vsfn $lbhomedir/system/php/loxberry-cli.ini /etc/php/7.3/cli/conf.d/20-loxberry-cli.ini >> $logfilename 2>&1 };
};

LOGOK "PHP logging settings changed.";

LOGINF "Installing daily cronjob for plugin update checks...";
$output = qx { rm -f $lbhomedir/system/cron/cron.daily/02-pluginsupdate.pl };
$output = qx { ln -f -s $lbhomedir/sbin/pluginsupdate.pl $lbhomedir/system/cron/cron.daily/02-pluginsupdate };

# Update Kernel and Firmware
if (-e "$lbhomedir/config/system/is_raspberry.cfg" && !-e "$lbhomedir/config/system/is_odroidxu3xu4.cfg") {
	LOGINF "Preparing Guru Meditation...";
	LOGINF "This will take some time now. We suggest getting a coffee or a second beer :-)";
	LOGINF "Upgrading system kernel and firmware. Takes up to 10 minutes or longer! Be patient and do NOT reboot!";

	my $output = qx { SKIP_WARNING=1 SKIP_BACKUP=1 BRANCH=stable /usr/bin/rpi-update f8c5a8734cde51ab94e07c204c97563a65a68636 };
	my $exitcode  = $? >> 8;
	if ($exitcode != 0) {
        	LOGERR "Error upgrading kernel and firmware - Error $exitcode";
        	LOGDEB $output;
                $errors++;
	} else {
        	LOGOK "Upgrading kernel and firmware successfully.";
	}
}

# Copy new ~/system/systemd to installation
LOGINF "Install ~/system/systemd to your Loxberry...";
&copy_to_loxberry('/system/systemd');

# Link usb-mount@.service
if ( -e "/etc/systemd/system/usb-mount@.service" ) {
	LOGINF "Remove /etc/systemd/system/usb-mount@.service...";
	unlink ("/etc/systemd/system/usb-mount@.service");
}
LOGINF "Install usb-mount@.service...";
system( "ln -s $lbhomedir/system/systemd/usb-mount@.service /etc/systemd/system/usb-mount@.service" );

LOGINF "Re-Install ssdpd service...";
if ( -e "/etc/systemd/system/ssdpd.service" ) {
	unlink ("/etc/systemd/system/ssdpd.service");
}
unlink ("$lbhomedir/data//system/ssdpd.service");
system ("ln -s $lbhomedir/system/systemd/ssdpd.service /etc/systemd/system/ssdpd.service");
system ("/bin/systemctl daemon-reload");

# Link loxberry.service
if ( -e "/etc/init.d/loxberry" ) {
	LOGINF "Remove old loxberry init script...";
	unlink ("/etc/init.d/loxberry");
}
if ( -e "/etc/systemd/system/loxberry.service" ) {
	LOGINF "Remove /etc/systemd/system/loxberry.service...";
	unlink ("/etc/systemd/system/loxberry.service");
}
LOGINF "Install loxberry.service...";
system( "ln -s $lbhomedir/system/systemd/loxberry.service /etc/systemd/system/loxberry.service" );

# Link createtmpfs.service
if ( -e "/etc/init.d/createtmpfsfoldersinit" ) {
	LOGINF "Remove old createtmpfs init script...";
	unlink ("/etc/init.d/createtmpfsfoldersinit");
}
if ( -e "/etc/systemd/system/createtmpfs.service" ) {
	LOGINF "Remove /etc/systemd/system/createtmpfs.service...";
	unlink ("/etc/systemd/system/createtmpfs.service");
}
LOGINF "Install createtmpfs.service...";
system( "ln -s $lbhomedir/system/systemd/createtmpfs.service /etc/systemd/system/createtmpfs.service" );

LOGINF "Disable already deinstalled dhcpcd.service...";
system( "systemctl disable dhcpcd" );

system ("/bin/systemctl daemon-reload");
system ("/bin/systemctl enable loxberry.service");
system ("/bin/systemctl enable createtmpfs.service");

if( -e $LoxBerry::System::PLUGINDATABASE ) {
	print "<WARN> Plugin database is already migrated. Skipping.";
} 

else {

	# Migrate plugindatabase.dat to plugindatabase.json
	my ($exitcode, $output) = LoxBerry::System::execute( 
		log => $log,
		intro => "Migrating plugindatabase to json file format",
		command => "perl $lbhomedir/sbin/loxberryupdate/migrate_plugindb_v2.pl",
		ok => "Plugin database migrated successfully.",
		error => "Migration returned an error."
	);
	LOGDEB $output;
	if($exitcode == 0) {
		LOGINF "The old plugin database is kept for any issues as plugindatabase.dat";
		unlink "$lbsdatadir/plugindatabase.dat-";
		unlink "$lbsdatadir/plugindatabase.bkp";
	} else {
		$errors++;
		LOGWARN "Because of errors, the old files of plugindatabase are kept for further investigation.";
	}
}

LOGINF "Installing new system crontab...";
mkdir "$lbhomedir/system/cron/cron.reboot";
`chown loxberry:loxberry $lbhomedir/system/cron/cron.reboot`;
&copy_to_loxberry('/system/cron/cron.d/lbdefaults');

# Clean apt
apt_update("clean");

## If this script needs a reboot, a reboot.required file will be created or appended
LOGWARN "Update file $0 requests a reboot of LoxBerry. Please reboot your LoxBerry after the installation has finished.";
reboot_required("LoxBerry Update requests a reboot.");

LOGOK "Update script $0 finished." if ($errors == 0);
LOGERR "Update script $0 finished with errors." if ($errors != 0);

# End of script
exit($errors);
