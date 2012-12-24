#!/bin/bash


# Settings
# ----------------------------------------------------------------------
# Couldn't figure out how to simulate a successful ssh password-less
# login so if you set this to a hostname on which you've set up ssh
# tests that rely upon this will be run and if not they will be skipped
SSH_KEYS_CONFIGURED_ON_THIS_HOST=


# float_test - Used to compare floating point numbers using awk. Returns
#              true or false based on evaluation of the expression
# ----------------------------------------------------------------------
testFloatsGreaterThan() {
    assertTrue "Simple test of greater than" \
        "float_test '3.0.1 > 2.9'"
}

testFloatsLessThan() {
    assertTrue "Simple test of less than" \
        "float_test '3.0.1 < 3.0.1.1'"
}

testFloatsLessThanOrEqual() {
    assertTrue "Simple test of less than or equal" \
        "float_test '3.0.1 <= 3.0.1'"
}

testErrorInputNonNumeric() {
    assertFalse "Returns false if non numeric input is used" \
        "float_test '3.0.1 < a'"
}


# login_with_key - Checks to see if ssh password-less login has been
#                  configured for a particular host
# ----------------------------------------------------------------------

testSshFailure() {
    assertFalse "Attempt to log into a non-existent host" \
        "login_with_key foo-host"
}


# See setting at the top of the test suite. If hostname is set the test
# will be run and will attempt to log into the host. If not the test
# will be skipped
testSshSuccess() {
    [ -z "$SSH_KEYS_CONFIGURED_ON_THIS_HOST" ] && startSkipping

    assertTrue "Attempt to log into a host with ssh keys configured" \
        "login_with_key $SSH_KEYS_CONFIGURED_ON_THIS_HOST"
}


# rsync_version - Parses out the version of rsync
# ----------------------------------------------------------------------
testRsyncVersion() {
    assertTrue "Version of rsync should be greater than 1" \
        "float_test '$(rsync_version) >= 1'"
}

testRemoteRsyncVersion() {
    [ -z "$SSH_KEYS_CONFIGURED_ON_THIS_HOST" ] && startSkipping

    assertTrue "Version of remote rsync should be greater than 1" \
        "float_test '$(rsync_version $SSH_KEYS_CONFIGURED_ON_THIS_HOST) > 1'"
}


# update_file_timestamps - Update timestamps on all files in a directory
# ----------------------------------------------------------------------
testUpdateFileTimestamps() {
    FILE_WITH_RECENT_MOD_DATE_CMD="find \$TEST_TMPDIR -type f -mtime 0 | wc -l"
    # Make some test files and give them a mod date way in the past
    FILE1=$(mktemp $TEST_TMPDIR/file1.XXXXXX)
    FILE2=$(mktemp $TEST_TMPDIR/file2.XXXXXX)
    FILE3=$(mktemp $TEST_TMPDIR/file3.XXXXXX)
    touch -t 200001010001 $TEST_TMPDIR/*
    # Verify that nothing has a recent mod date
    assertEquals 0 $(eval $FILE_WITH_RECENT_MOD_DATE_CMD)
    # Run the method to update all file timestamps in the directory
    update_file_timestamps $TEST_TMPDIR
    # Run the same find command and it should find all our test files
    assertEquals 3 $(eval $FILE_WITH_RECENT_MOD_DATE_CMD)
}


# verify_prereqs - Used to attempt to location programs needed by the
#                  script and return true/false if found
# ----------------------------------------------------------------------

testVerifyPrereqsSuccess() {
    assertTrue "ls should be present on all systems" \
        "verify_prereqs ls"
}

testVerifyPrereqsFailure() {
    assertFalse "blorbFoo is a made up command and should fail" \
        "verify_prereqs blorbFoo"
}


# test suite setup and execution
# ----------------------------------------------------------------------
TEST_TMPDIR=
oneTimeSetUp() {
    TEST_TMPDIR=$(mktemp -d /tmp/inotify-move-tests.XXXXXX)
}

oneTimeTearDown() {
    rm -fr $TEST_TMPDIR
}

# Base directory of this project is one directory up from this script
BASE_DIR="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/.."

# load code under test
. $BASE_DIR/src/inotify-move.sh

# Run the tests
. $BASE_DIR/test/shunit2/src/shunit2
