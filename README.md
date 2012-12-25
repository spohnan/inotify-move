## inotify-move.sh ##

A shell script that watches a directory and uses rsync and ssh for transfer, compression and encryption with notification of file changes provided by inotify-tools.

Notable behavior is that it _moves_ files from the local to remote directory instead of the usual sync you'd expect from rsync.