#!/bin/sh
# ESXi 5.1+ host automated asynchronous shutdown script
# Tested on the free version of VMware ESXi 6
# Asynchronous shutdown added by Andrey Babak <ababak@gmail.com>, 2016

# Specify log file path
LOG_FILE=/vmfs/volumes/DL360G7_disk/esxidown.log

exec 2>>${LOG_FILE}

message () {
	echo "$(date '+%D %H:%M:%S') [esxidown] $1">>${LOG_FILE}
}


# these are the VM IDs to shutdown in the order specified
# use the SSH shell, run "vim-cmd vmsvc/getallvms" to get ID numbers
# specify IDs separated by a space
SERVERIDS=$(vim-cmd vmsvc/getallvms | sed -e '1d' -e 's/ \[.*$//' | awk '$1 ~ /^[0-9]+$/ {print $1}')
VALIDATEIDS=''

# New variable to allow script testing, assuming the vim commands all work to issue shutdowns
# can be "0" or "1"
TEST=0

# script waits WAIT_TRYS times, WAIT_TIME seconds each time
# number of times to wait for a VM to shutdown cleanly before forcing power off.
WAIT_TRIES=20

# how long to wait in seconds each time for a VM to shutdown.
WAIT_TIME=10

# ------ DON'T CHANGE BELOW THIS LINE ------

# enter maintenance mode immediately
message "Entering maintenance mode..."
if [ $TEST -eq 0 ]; then
    esxcli system maintenanceMode set -e true -t 0 &
fi

# read each line as a server ID and shutdown/poweroff
for SRVID in $SERVERIDS
do
    vim-cmd vmsvc/power.getstate $SRVID | grep -i "off\|Suspended" > /dev/null 2<&1
    STATUS=$?

    if [ $STATUS -ne 0 ]; then
        message "Attempting shutdown of guest VM ID $SRVID"
        if [ $TEST -eq 0 ]; then
            vim-cmd vmsvc/power.shutdown $SRVID
        fi
        VALIDATEIDS="$VALIDATEIDS $SRVID"
    else
        message "Guest VM ID $SRVID already off"
    fi
done

# read each line as a server ID and shutdown/poweroff
TRY=1
while [ $TRY -le $WAIT_TRIES ]
do
	SLOWIDS=''
	for SRVID in $VALIDATEIDS
	do
		vim-cmd vmsvc/power.getstate $SRVID | grep -i "off\|Suspended" > /dev/null 2<&1
		STATUS=$?

		if [ $STATUS -ne 0 ]; then
			# if the vm is not off, wait for it to shut down
			message "Waiting for guest VM ID $SRVID to shutdown (attempt #$TRY)"
			SLOWIDS="$SLOWIDS $SRVID"
		fi
	done
	VALIDATEIDS="$SLOWIDS"
    if [ "$VALIDATEIDS"!="" ]; then
		sleep $WAIT_TIME
	else
		message "Everybody is sleeping"
		break
	fi
	TRY=$((TRY + 1))
done

for SRVID in $VALIDATEIDS
do
	# force power off and wait a little (you could use vmsvc/power.suspend here instead)
	message "Unable to gracefully shutdown guest VM ID $SRVID, forcing power off"
	if [ $TEST -eq 0 ]; then
		vim-cmd vmsvc/power.off $SRVID
	fi
done


# guest vm shutdown complete
message "Guest VM shutdown complete"

# shutdown the ESXi host
message "Shutting down ESXi host after 10 seconds"
if [ $TEST -eq 0 ]; then
    esxcli system shutdown poweroff -d 10 -r "Automated ESXi host shutdown - esxidown.sh"
fi

# exit maintenance mode immediately before server has a chance to shutdown/power off
# NOTE: it is possible for this to fail, leaving the server in maintenance mode on reboot!
message "Exiting maintenance mode"
if [ $TEST -eq 0 ]; then
    esxcli system maintenanceMode set -e false -t 0
fi

# exit the session
exit
