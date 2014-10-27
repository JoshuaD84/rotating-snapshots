#!/usr/bin/bash

#this is a simple bash script that can be used to make sure the backup script is
#generating snapshots, links, etc. properly.  It loops the backup script N times
#and sets the date for that snapshot to today-i

for((i=$1; $i >= 0; i--)) ; do 
	./backup.sh $i
done
