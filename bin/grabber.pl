#!/usr/bin/perl

# grabber for fetching data from mirobots

# Copyright 2018 Michael Schlenstedt, michael@loxberry.de
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

use strict;
use warnings;

##########################################################################
# Modules
##########################################################################

use LoxBerry::System;
use LoxBerry::Log;
use JSON qw( decode_json ); 
use File::Copy;
use Getopt::Long;
use LoxBerry::IO;
use Encode qw(decode encode);

##########################################################################
# Read Settings
##########################################################################

# Version of this script
my $version = "1.0.5.0";

my $cfg         = new Config::Simple("$lbpconfigdir/mirobot2lox.cfg");
my $getdata     = $cfg->param("MAIN.GETDATA");
my $udpport     = $cfg->param("MAIN.UDPPORT");
my $ms          = $cfg->param("MAIN.MS");

# Read language phrases
my %L = LoxBerry::System::readlanguage("language.ini");

# Create a logging object
my $log = LoxBerry::Log->new ( 	
			name => 'grabber',
			package => 'mirobot2lox-ng',
			logdir => "$lbplogdir",
);

# Commandline options
my $verbose = '';

GetOptions ('verbose' => \$verbose,
            'quiet'   => sub { $verbose = 0 });

# Due to a bug in the Logging routine, set the loglevel fix to 3
#$log->loglevel(3);
if ($verbose) {
	$log->stdout(1);
	$log->loglevel(7);
}
if ($log->loglevel eq "7") {
	$LoxBerry::IO::DEBUG = 1;
}


LOGSTART "MiRobo2Lox-NG GRABBER process started";
LOGDEB "This is $0 Version $version";

# Exit if fetching is not active
if ( !$getdata ) {
	LOGWARN "Fetching data is not active. Exit.";
	&exit;
}

LOGINF "Fetching Data from Robots";

# Clean HTML
unlink ("$lbplogdir/robotsdata.txt.tmp");

for (my $i=1; $i<6; $i++) {

	if ( !$cfg->param("ROBOT$i" . ".ACTIVE") ) {
		LOGINF "Robot $i is not active - skipping...";
		next;
	}

	my $ip = $cfg->param( "ROBOT$i" . ".IP");
	my $token = $cfg->param( "ROBOT$i" . ".TOKEN");

	LOGINF "Fetching Status Data for Robot $i...";
	LOGINF "$lbpbindir/mirobo_wrapper.sh $ip $token status none 2";
	my $json = `$lbpbindir/mirobo_wrapper.sh $ip $token status none 2`;
	if ($json =~ /Unable to discover/) {
		LOGERR "Robot $i isn't reachable - skipping...";
		next;
	}
	my $djson1 = decode_json( $json );
	
	# Unknown state
	if ( $djson1->{'state'} > 14 ) {
		$djson1->{'state'} = "16";
	}
	
	# Unknown error
	if ( $djson1->{'error_code'} > 20 ) {
		$djson1->{'error_code'} = "21";
	}

	# If batt is fully charged in Dock, set state to 15
	if ( $djson1->{'state'} eq "8" && $djson1->{'battery'} eq "100" ) {
		$djson1->{'state'} = "15";
	}

	LOGINF "Fetching Consumables Data for Robot $i...";
	LOGINF "$lbpbindir/mirobo_wrapper.sh $ip $token consumable_status none 2";
	$json = `$lbpbindir/mirobo_wrapper.sh $ip $token consumable_status none 2`;
	my $djson2 = decode_json( $json );

	LOGINF "Fetching Cleaning Data for Robot $i...";
	LOGINF "$lbpbindir/mirobo_wrapper.sh $ip $token clean_history none 2";
	$json = `$lbpbindir/mirobo_wrapper.sh $ip $token clean_history none 2`;
	my $djson3 = decode_json( $json );

	# Now
	my $thuman = localtime();
	my $t = time();

	# Calculations
	$djson1->{'clean_area'} = sprintf("%.3f", $djson1->{'clean_area'} / 1000000);
	$djson1->{'clean_time'} = sprintf("%.3f", $djson1->{'clean_time'} / 60);
	$djson2->{'main_brush_work_time'} = sprintf("%.3f", $djson2->{'main_brush_work_time'} / 60 / 60);
	$djson2->{'sensor_dirty_time'} = sprintf("%.3f", $djson2->{'sensor_dirty_time'} / 60 / 60);
	$djson2->{'side_brush_work_time'} = sprintf("%.3f", $djson2->{'side_brush_work_time'} / 60 / 60);
	$djson2->{'filter_work_time'} = sprintf("%.3f", $djson2->{'filter_work_time'} / 60 / 60);
	$djson3->[0] = sprintf("%.3f", $djson3->[0] / 60 / 60); # Total Clean time
	$djson3->[1] = sprintf("%.3f", $djson3->[1] / 1000000); # Total clean area
	my $last = $t - $djson3->[3]->[0];
	$last = sprintf("%.3f", $last / 60); # Minutes since last cleaning
	my $main_brush_work_percent = sprintf("%.0f", 100/300*(300-$djson2->{'main_brush_work_time'}));
	$main_brush_work_percent = $main_brush_work_percent < 0 ? "0" : $main_brush_work_percent;
	my $sensor_dirty_percent = sprintf("%.0f", 100/30*(30-$djson2->{'sensor_dirty_time'}));
	$sensor_dirty_percent = $sensor_dirty_percent < 0 ? "0" : $sensor_dirty_percent;
	my $side_brush_work_percent = sprintf("%.0f", 100/200*(200-$djson2->{'side_brush_work_time'}));
	$side_brush_work_percent = $side_brush_work_percent < 0 ? "0" : $side_brush_work_percent;
	my $filter_work_percent = sprintf("%.0f", 100/150*(150-$djson2->{'filter_work_time'}));
	$filter_work_percent = $filter_work_percent < 0 ? "0" : $filter_work_percent;
	my $main_brush_work_left = sprintf("%.0f", 300-$djson2->{'main_brush_work_time'});
	$main_brush_work_left = $main_brush_work_left < 0 ? "0" : $main_brush_work_left;
	my $sensor_dirty_left = sprintf("%.0f", 30-$djson2->{'sensor_dirty_time'});
	$sensor_dirty_left = $sensor_dirty_left < 0 ? "0" : $sensor_dirty_left;
	my $side_brush_work_left = sprintf("%.0f", 200-$djson2->{'side_brush_work_time'});
	$side_brush_work_left = $side_brush_work_left < 0 ? "0" : $side_brush_work_left;
	my $filter_work_left = sprintf("%.0f", 150-$djson2->{'filter_work_time'});
	$filter_work_left = $filter_work_left < 0 ? "0" : $filter_work_left;

	# UDP
	my %data_to_send;
	if ( $cfg->param("MAIN.SENDUDP") ) {
		LOGINF "Sending UDP data from Robot$i to MS$ms";
		$data_to_send{'now_human'} = $thuman;
		$data_to_send{'now'} = $t;
		$data_to_send{'state_code'} = $djson1->{'state'};
		$data_to_send{'state_txt'} = Encode::decode("UTF-8", $L{"GRABBER.STATE$djson1->{'state'}"});
		$data_to_send{'map_present'} = $djson1->{'map_present'};
		$data_to_send{'in_cleaning'} = $djson1->{'in_cleaning'};
		$data_to_send{'fan_power'} = $djson1->{'fan_power'};
		$data_to_send{'msg_seq'} = $djson1->{'msg_seq'};
		$data_to_send{'battery'} = $djson1->{'battery'};
		$data_to_send{'msg_ver'} = $djson1->{'msg_ver'};
		$data_to_send{'cur_clean_time'} = $djson1->{'clean_time'};
		$data_to_send{'dnd_enabled'} = $djson1->{'dnd_enabled'};
		$data_to_send{'cur_clean_area'} = $djson1->{'clean_area'};
		$data_to_send{'error_code'} = $djson1->{'error_code'};
		$data_to_send{'error_txt'} = Encode::decode("UTF-8", $L{"GRABBER.ERROR$djson1->{'error_code'}"});
		$data_to_send{'main_brush_work_time'} = $djson2->{'main_brush_work_time'};
		$data_to_send{'main_brush_work_percent'} = $main_brush_work_percent;
		$data_to_send{'main_brush_work_left'} = $main_brush_work_left;
		$data_to_send{'sensor_dirty_time'} = $djson2->{'sensor_dirty_time'};
		$data_to_send{'sensor_dirty_percent'} = $sensor_dirty_percent;
		$data_to_send{'sensor_dirty_left'} = $sensor_dirty_left;
		$data_to_send{'side_brush_work_time'} = $djson2->{'side_brush_work_time'};
		$data_to_send{'side_brush_work_percent'} = $side_brush_work_percent;
		$data_to_send{'side_brush_work_left'} = $side_brush_work_left;
		$data_to_send{'filter_work_time'} = $djson2->{'filter_work_time'};
		$data_to_send{'filter_work_percent'} = $filter_work_percent;
		$data_to_send{'filter_work_left'} = $filter_work_left;
		$data_to_send{'total_clean_time'} = $djson3->[0];
		$data_to_send{'total_clean_area'} = $djson3->[1];
		$data_to_send{'total_cleanups'} = $djson3->[2];
		$data_to_send{'minutes_since_last_clean'} = $last;
	
		my $response = LoxBerry::IO::msudp_send_mem($ms, $udpport, "MiRobot$i", %data_to_send);
		#my $response = LoxBerry::IO::msudp_send($ms, $udpport, "MiRobot$i", %data_to_send);
		if (! $response) {
			LOGERR "Error sending UDP data from Robot$i to MS$ms";
    		} else {
			LOGINF "Sending UDP data from Robot$i to MS$ms successfully.";
		}
	}

	# HTML
	my $error = 0;
	open (F,">>$lbplogdir/robotsdata.txt.tmp") or $error = 1;
	if ($error) {
		LOGWARN "Cannot open $lbplogdir/robotsdata.txt for writing.";
	} else {
		print F "MiRobot$i: now_human=$thuman\n";
		print F "MiRobot$i: now=$t\n";
		print F "MiRobot$i: state_code=$djson1->{'state'}\n";
		print F "MiRobot$i: state_txt=" . Encode::decode("UTF-8", $L{"GRABBER.STATE$djson1->{'state'}"}) . "\n";
		print F "MiRobot$i: map_present=$djson1->{'map_present'}\n";
		print F "MiRobot$i: in_cleaning=$djson1->{'in_cleaning'}\n";
		print F "MiRobot$i: fan_power=$djson1->{'fan_power'}\n";
		print F "MiRobot$i: msg_seq=$djson1->{'msg_seq'}\n";
		print F "MiRobot$i: battery=$djson1->{'battery'}\n";
		print F "MiRobot$i: msg_ver=$djson1->{'msg_ver'}\n";
		print F "MiRobot$i: cur_clean_time=$djson1->{'clean_time'}\n";
		print F "MiRobot$i: dnd_enabled=$djson1->{'dnd_enabled'}\n";
		print F "MiRobot$i: cur_clean_area=$djson1->{'clean_area'}\n";
		print F "MiRobot$i: error_code=$djson1->{'error_code'}\n";
		print F "MiRobot$i: error_txt=" . Encode::decode("UTF-8", $L{"GRABBER.ERROR$djson1->{'error_code'}"}) . "\n";
		print F "MiRobot$i: main_brush_work_time=$djson2->{'main_brush_work_time'}\n";
		print F "MiRobot$i: main_brush_work_percent=$main_brush_work_percent\n";
		print F "MiRobot$i: main_brush_work_left=$main_brush_work_left\n";
		print F "MiRobot$i: sensor_dirty_time=$djson2->{'sensor_dirty_time'}\n";
		print F "MiRobot$i: sensor_dirty_percent=$sensor_dirty_percent\n";
		print F "MiRobot$i: sensor_dirty_left=$sensor_dirty_left\n";
		print F "MiRobot$i: side_brush_work_time=$djson2->{'side_brush_work_time'}\n";
		print F "MiRobot$i: side_brush_work_percent=$side_brush_work_percent\n";
		print F "MiRobot$i: side_brush_work_left=$side_brush_work_left\n";
		print F "MiRobot$i: filter_work_time=$djson2->{'filter_work_time'}\n";
		print F "MiRobot$i: filter_work_percent=$filter_work_percent\n";
		print F "MiRobot$i: filter_work_left=$filter_work_left\n";
		print F "MiRobot$i: total_clean_time=$djson3->[0]\n";
		print F "MiRobot$i: total_clean_area=$djson3->[1]\n";
		print F "MiRobot$i: total_cleanups=$djson3->[2]\n";
		print F "MiRobot$i: minutes_since_last_clean=$last\n";
		close (F);
	}

	# VTI
	my %data_to_vti;
	$data_to_vti{"MiRobot$i state"} = $L{"GRABBER.STATE$djson1->{'state'}"};
	$data_to_vti{"MiRobot$i error"} = $L{"GRABBER.ERROR$djson1->{'error_code'}"};
	my $response = LoxBerry::IO::mshttp_send_mem($ms, %data_to_vti);

}

# End
system ("mv $lbplogdir/robotsdata.txt.tmp $lbplogdir/robotsdata.txt");
exit;


END
{
	LOGEND;
}

