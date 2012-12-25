#!/bin/bash
#
# inotify-move.sh
#
# Uses rsync and ssh for transfer, compression and encryption
# Notification of file changes provided by inotify-tools which
# is available in rpm packaging through the EPEL repo.
# https://github.com/rvoicilas/inotify-tools/wiki/
#
# Assumes you've set up your ssh key for password-less login
# on the remote machine prior to running.
#
# Usage: inotify-move.sh LOCAL_DIR REMOTE_USER@REMOTE_HOST:$DIRECTORY [$LOG]


# Parse command line options
# ---------------------------------------------------------------------------
LOCAL_DIR=$1
REMOTE_USER=$(echo $2 | cut -d@ -f1)
REMOTE_HOST=$(echo $2 | cut -d: -f1 | cut -d@ -f2 )
REMOTE_DIR=$(echo $2 | cut -d: -f2 )
LOG_FILE=$3


# Allow for easy overriding of a set of default settings
# ---------------------------------------------------------------------------
RSYNC_OPTS=
if [ -z "$RSYNC_OPTS" ] ; then
    RSYNC_OPTS="--partial -avz -e ssh --log-file=$LOG_FILE"
fi


# verify_prereqs PROGRAM_NAME
#
# Attempt to locate an external program we'll need to use and return an
# error if not found
# ---------------------------------------------------------------------------
verify_prereqs() {
    if ! command -v $1 >/dev/null 2>&1 ; then
        echo "Error: $1 is required but cannot be found"
        return 1
    fi
}


# float_test "NUMBER COMPARISON_OPERATOR NUMBER"
#
# Floating point number comparison to compare rsync version numbers
# ---------------------------------------------------------------------------
float_test() {
	echo | awk 'END { exit (!('"$1"')); }'
}

# login_with_key REMOTE_HOST
#
# Checks to see if ssh password-less login has been configured for a particular host
# ---------------------------------------------------------------------------
login_with_key() {
    ssh -oBatchMode=yes $1 "hostname" >/dev/null 2>&1
    return $? # return value of the ssh command
}


# rsync_version [REMOTE_HOST]
#
# Return the version of rsync. An optional hostname argument can be given to this
# method and if ssh password-less login has been configured it will check the version
# on the remote host
# ---------------------------------------------------------------------------
rsync_version() {
    CMD="rsync --version | grep version | awk '{print \$3}'" # Command to get just version num
    RETVAL=1 # Initialize to a value that evaluates to false

    if [ -z $1 ] && $(verify_prereqs rsync) ; then
        RETVAL=$(eval $CMD) # Check locally
    elif login_with_key $1 ; then
        RETVAL=$(ssh $1 -C $CMD) # Check remote
    fi
    echo $RETVAL
}


# rsync_supports_remove_option VERSION
#
# The --remove-source-files option is available in rsync v2.6.9 onwards. (RHEL 6.0+)
# ---------------------------------------------------------------------------
rsync_supports_remove_option() {
    float_test "$1 >= 2.6.9" && return $?
}


# update_file_timestamps DIRECTORY
#
# Use the touch command to update the modified timestamps of all files within
# the given directory. Will become a no-op if directory cannot be found or modified
# ---------------------------------------------------------------------------
update_file_timestamps() {
    if [ -d $1 ] ; then
        find $1 -exec touch {} \;
    fi
}

# init_inotify_move
#
# This is the main body of the script. Update the timestamps of any files in the
# local directory that may have been added since we last ran this script. Then
# run the inotifywait command to let us know when files have been added. Once
# a file has been identified use one of two methods to move to the remote system
# depending on the version of rsync installed.
# ---------------------------------------------------------------------------
init_inotify_move() {
    # In a subshell we'll wait a couple of seconds for the commands below to execute
    # and then refresh the timestamp on any existing files at script startup.
    (sleep 5; update_file_timestamps $LOCAL_DIR) &

    USE_REMOVE_OPTION=false
    if rsync_supports_remove_option $(rsync_version) && \
        rsync_supports_remove_option $(rsync_version "$REMOTE_USER@$REMOTE_HOST") ; then
        USE_REMOVE_OPTION=true
    fi

    # Sync in response to inotify events
    inotifywait -m --timefmt '%d/%m/%y %H:%M' --format '%T %w %f' -e close_write $LOCAL_DIR | \
    while read date time dir file; do
        FILECHANGE=${dir}${file}  # File to be transferred and removed

        # Use rsync remove command if possible. If not available, then
        # check for the successful exit value and just remove the file
        if $USE_REMOVE_OPTION ; then
            rsync $RSYNC_OPTS --remove-source-files $FILECHANGE $REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR
        else
            rsync $RSYNC_OPTS $FILECHANGE $REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR && rm $FILECHANGE
        fi
    done
}


# If all the proper arguments have been supplied run the program
# ---------------------------------------------------------------------------
if [ -d $LOCAL_DIR ] && [ ! -z $REMOTE_USER ] && [ ! -z $REMOTE_HOST ] \
    && [ ! -z $REMOTE_DIR ] && verify_prereqs "inotifywait" ; then

     # A separate check just so we can give a more helpful error message if it fails
     if login_with_key "$REMOTE_USER@$REMOTE_HOST" ; then
        init_inotify_move
     else
        echo "Error: ssh login to $REMOTE_USER@$REMOTE_HOST failed"
     fi
else
    echo "Usage: inotify-move.sh LOCAL_DIR REMOTE_USER@REMOTE_HOST:REMOTE_DIR [LOG_FILE]"
fi
