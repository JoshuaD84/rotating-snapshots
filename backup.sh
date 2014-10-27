#!/bin/bash
#author: 	Joshua Hartwell
#website:	www.joshuad.net
#license:	GNU GPL v3.0
#version:	1.0

#check to see if the less common necessary commands are here
command -v rsync >/dev/null 2>&1 || { echo >&2 "I require rsync but it's not installed.  Aborting."; exit 1; }
command -v ssh >/dev/null 2>&1 || { echo >&2 "I require ssh but it's not installed.  Aborting."; exit 1; }
command -v scp >/dev/null 2>&1 || { echo >&2 "I require scp but it's not installed.  Aborting."; exit 1; }

my_dir=`readlink -f $(dirname "$0")`

source "$my_dir/config.sh"

snapshot_format="%Y-%m-%d" 	#if you change this, you need to rename any snapshots made previous 
							#to the change, or you lose all the linking and auto-removal
							#of previous snapshots.  Not the end of the world
							#just rename the most recent snapshot to get linking back.

#commands, to avoid any path errors
RSYNC=$(command -v rsync)
DATE=$(command -v date)       
ECHO="$(command -v echo) -e"    
RM=$(command -v rm)
SSH=$(command -v ssh)     
TEE="$(command -v tee) -a"
SCP=$(command -v scp)
MKDIR="$(command -v mkdir) -p"

#For testing purposes, allow a date offset to be set by command line
testing_day_offset="0"
if [ -n "$1" ] ; then 
	$ECHO "Command line day offset is set to $1" >> $local_log
	testing_day_offset=$1
fi;

#get the current date, save it a few different ways for easy reference.     
now=$($DATE +$snapshot_format --date="$testing_day_offset days ago")
now_month=$($DATE +%m --date="$now")
now_day=$($DATE +%d --date="$now")

$ECHO ================================================== >> $local_log  
$ECHO "            begin snapshot $now"                  >> $local_log  
$ECHO -------------------------------------------------- >> $local_log  

new_snapshot=$snapshot_root$now

#If the snapshot root folder doesn't exist, make it. 
if [ ! -d $snapshot_root ]; then
	$MKDIR -p $snapshot_root
	$ECHO "$snapshot_root did not exist, created it and any necessary parent directories" >> $local_log
fi

#find the most recent snapshot to give to rsync to link from. Should be yesterday's, but we look back
#each day for two years until we find one. We want to be sure that we find one if it's there. 
previous_snapshot=""
for((i=1; $i<=730; i++)); do
	test_snapshot=$snapshot_root$($DATE +$snapshot_format --date="$now -$i days")
	if [ -d $test_snapshot ]; then
		previous_snapshot=$test_snapshot
		break
	fi
done

#check if the current snapshot already exists
if [ -d $new_snapshot ]; then
	#the current snapshot's directory is already here, that's very weird. 
	$ECHO "Warning! Snapshot $new_snapshot already exists. Syncing into that folder. This shouldn't cause any problems, but it's definitely unexpected. Whatever was there is being replaced by a fresh snapshot. This could be due to someone starting the backup script manually. Or maybe the server's date has been changed. You might want to go check on the backups, but I'm going to backup to $new_snapshot in the meantime." >> $local_log
fi

#check if the previous snapshot exists
if [[ -n "$previous_snapshot" && -d $previous_snapshot ]] ; then
	link_from_flag="--link-dest=$previous_snapshot"
	$ECHO "Using Snapshot $previous_snapshot as the link target" >> $local_log 
else
	$ECHO "Warning! Could not find a previous snapshot to link from. This should only happen the very first time this script is run. If it happened otherwise, something is wrong with the previous snapshots. Please verify the data on the backup server." >> $local_log

fi

#apply the bandwidth limit if set in config.sh
if [ ! -z $bandwidth_limit ] ; then 
	bandwidth_limit_flag="--bwlimit=$bandwidth_limit"
	$ECHO "Bandwidth limit set to $bandwidth_limit kbs" >> $local_log
else 
	$ECHO "No bandwidth limit set" >> $local_log
fi

#if the detect-renamed patch is compiled in, use it.
detect_test=$RSYNC --help 2>&1 | grep "detect-renamed"
if [ -z $detect_test ] ; then
	detect_renamed_flag=""
	$ECHO "Detect rename is not compiled into srync, so it is not being not used" >> $local_log
else 
	detect_renamed_flag="--detected-renamed"
	$ECHO "Detect rename seems to be compiled in to rsync, so it is being used" >> $local_log
fi

if [ -f "$excludes" ] ; then
	excludes_flag="--exclude-from $excludes"
	$ECHO "Exludes file used: '$excludes'" >> $local_log
else 
	$ECHO "No excludes filed used" >> $local_log
fi

#Everything else was just setup, this is where the magic happens
#create the new snapshot and link to the prevoius snapshot

$ECHO "\n----rsync begin----\n" >> $local_log

$RSYNC $detect_renamed_flag --verbose --archive --compress --human-readable --delete --delete-excluded --links --hard-links $link_from_flag $bandwidth_limit_flag $excludes_flag -e $SSH $snapshot_source $new_snapshot >> $local_log 2>&1

$ECHO "\n----rsync end----\n" >> $local_log

#Now we delete the old snapshots, if necessary.

#if we're on the first day of the first month of the year, delete any eclipsed yearly snapshots
if [ $now_month -eq 1 ] && [ $now_day -eq 1 ] ; then 
	target=`$DATE +$snapshot_format --date="$now -$years_to_keep years"`
	delete_snapshot=$snapshot_root$target
	if [ -d $delete_snapshot ] ; then
		$RM -rf $delete_snapshot | $TEE $local_log 2>&1
		$ECHO "yearly snapshot $delete_snapshot removed, it was $years_to_keep year(s) old" >> $local_log
	fi
fi

#if we're on the first day of the month, delete any eclipsed monthly snapshots
if [ $now_day -eq 1 ] ; then
	target=`$DATE +$snapshot_format --date="$now -$months_to_keep months"`
	target_month=`$DATE +%m --date="$target"`
	delete_snapshot=$snapshot_root$target

	if [ -d $delete_snapshot ] ; then
	
		if [ $target_month -eq 1 ] ; then
			$ECHO "monthly snapshot $delete_snapshot NOT removed, it was $months_to_keep month(s) old, but it is preserved as a yearly snapshot" >> $local_log
		else
			$RM -rf $delete_snapshot | $TEE $local_log 2>&1
			$ECHO "monthly snapshot $delete_snapshot removed, it was $months_to_keep month(s) old" >> $local_log
		fi
	else
		$ECHO "Monthly $delete_snapshot not removed, it doesn't exist" >> $local_log
	fi
fi

target_month=`$DATE +%m --date="$now -$days_to_keep days"`
target_day=`$DATE +%d --date="$now -$days_to_keep days"`
target=`$DATE +$snapshot_format --date="$now -$days_to_keep days"`
delete_snapshot=$snapshot_root$target

#now delete any eclipsed daily snapshots
if [ -d $delete_snapshot ] ; then
	
	if [ $target_month -eq 1 ] && [ $target_day -eq 1 ]; then
		$ECHO "daily snapshot $delete_snapshot NOT removed, it is $days_to_keep days old, but it is preserved as a yearly snapshot" >> $local_log
	elif [ $target_day -eq 1 ] ; then
		$ECHO "daily snapshot $delete_snapshot NOT removed, it is $days_to_keep days old, but it is preserved as a monthly snapshot" >> $local_log
	else
		$RM -rf $delete_snapshot | $TEE $local_log | $TEE $local_log 2>&1
		$ECHO "daily snapshot $delete_snapshot removed, it was $days_to_keep days old" >> $local_log
	fi
else
	$ECHO "Daily $delete_snapshot not removed, it doesn't exist" >> $local_log   
fi 

$ECHO -------------------------------------------------- >> $local_log
$ECHO "            end snapshot $now"                    >> $local_log
$ECHO ================================================== >> $local_log
$ECHO "" >> $local_log 
$ECHO "" >> $local_log 

#Finally, we copy the local log to the remote server and replace the one that was there.
#we really don't care about the output of this command and it's hard to log, since we're accessing the log
#as we would be trying to write to it.  We could use a swap file (and then upload it again) but it all gets
#really cumbersome. The remote server will know if the log didn't upload because it won't have been
#updated.  
$SCP $local_log $remote_log > /dev/null 2>&1


