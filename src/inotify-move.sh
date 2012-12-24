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


LOCAL_DIR=$1
REMOTE_USER=$(echo $2 | cut -d@ -f1)
REMOTE_HOST=$(echo $2 | cut -d: -f1 | cut -d@ -f2 )
REMOTE_DIR=$(echo $2 | cut -d: -f2 )
LOG_FILE=$3

RSYNC_VERSION_THAT_SUPPORTS_REMOVE_OPTION="2.6.9"
RSYNC_OPTS="--partial -avz -e ssh --log-file=$LOG_FILE"

# Attempt to locate an external program we'll need to use and return an
# error if not found
verify_prereqs() {
    if ! command -v $1 >/dev/null 2>&1 ; then
        echo "Error: $1 is required but cannot be found"
        return 1
    fi
}

# Floating point number comparison to compare rsync version numbers
float_test() {
	echo | awk 'END { exit (!('"$1"')); }'
}

# Checks to see if ssh password-less login has been configured for a particular host
login_with_key() {
    ssh -oBatchMode=yes $1 "hostname" >/dev/null 2>&1
    return $? # return value of the ssh command
}

# Return the version of rsync. An optional hostname argument can be given to this
# method and if ssh password-less login has been configured it will check the version
# on the remote host
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


# The --remove-source-files option is available in rsync v2.6.9 onwards. (RHEL 6.0+)
rsync_supports_remove_option() {
    if [ -z $1 ] ; then
        float_test "$(rsync_version) >= $RSYNC_VERSION_THAT_SUPPORTS_REMOVE_OPTION" && return 0
    else
        float_test "$(rsync_version $1) >= $RSYNC_VERSION_THAT_SUPPORTS_REMOVE_OPTION" && return 0
    fi
}

update_file_timestamps() {
    if [ -d $1 ] ; then
        find $1 -exec touch {} \;
    fi
}

init_inotify_move() {
    # In a parallel subshell we'll wait a couple of seconds for the commands below to execute
    # and then refresh the timestamp on any existing files at script startup.
    (sleep 5; update_file_timestamps $LOCAL_DIR) &

    # Sync in response to inotify events
    inotifywait -m --timefmt '%d/%m/%y %H:%M' --format '%T %w %f' -e close_write $LOCAL_DIR | \
    while read date time dir file; do
        FILECHANGE=${dir}${file}  # File to be transferred and removed

        # Use rsync remove command if possible. If not available, then
        # check for the succesful exit value and just remove the file
        if rsync_supports_remove_option && rsync_supports_remove_option "$REMOTE_USER@$REMOTE_HOST"; then
            rsync $RSYNC_OPTS --remove-source-files $FILECHANGE $REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR
        else
            rsync $RSYNC_OPTS $FILECHANGE $REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR && rm $FILECHANGE
        fi
    done
}

if [ ! -z $LOCAL_DIR ] && [ ! -z $REMOTE_USER ] && [ ! -z $REMOTE_HOST ] && [ ! -z $REMOTE_DIR ] ; then
    init_inotify_move
fi
