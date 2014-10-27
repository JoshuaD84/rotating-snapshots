#!/usr/bin/bash

#to use this file, please copy it and rename it config.sh

my_dir=`readlink -f $(dirname "$0")`

days_to_keep=10  	#please note that if you shorten these times, after the script has been running for a while
months_to_keep=6	#certain snapshots may never be removed
years_to_keep=3		#You can (of course) always remove any of those snapshots by hand and it will do no
					#harm (as long as at least one snapshot remains)

bandwidth_limit=1000 #measured in KiB/s, even though rsync's documentation says KB/s. The rsync docs are bugged

snapshot_source="user@host:/absolute/path/to/remote/source/"; #Make sure this ends with a trailing slash
snapshot_root="/absolute/path/to/local/snapshot/location/" #Make sure this ends with a trailing slash

excludes="$my_dir/excludes.rsync"
local_log="$my_dir/backup.log"
remote_log="user@host:/absolute/path/to/remote/log/backup.log"

