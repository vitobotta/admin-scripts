#!/bin/bash

# ---------------------------------------------------------------------------------------------
# Uses the latest backup taken with the xtrabackup script to create a compressed archive;
# also removes archives older than 10 days
# ---------------------------------------------------------------------------------------------

set -e

LOG_FILE="/tmp/archive-db-backup-$(date +%Y-%m-%d-%H.%M.%S).log"
echo "" > $LOG_FILE

die () {
  echo -e 1>&2 "$@"
  exit 1
}

fail () {
  die "...FAILED! See $LOG_FILE for details - aborting.\n"
}


echo "Preparing copy of the latest backup available on $HOSTNAME...

LAST_BACKUP_TIMESTAMP=`find /backup/mysql/ -mindepth 2 -maxdepth 2 -type d -exec ls -dt {} \+ | head -1 | rev | cut -d '/' -f 1 | rev`
DESTINATION="/backup/mysql/archives"
ARCHIVE="$DESTINATION/production-data.$(date +%Y-%m-%d-%H.%M.%S).tgz"
TEMP_DIRECTORY=`mktemp -d`

mkdir -vp $DESTINATION

/admin-scripts/backup/xtrabackup.sh restore $LAST_BACKUP_TIMESTAMP $TEMP_DIRECTORY

echo "Prepared a copy of the data, now creating a compressed archive..."

/usr/bin/ionice -c2 -n7 tar cvfz $ARCHIVE $TEMP_DIRECTORY &> $LOG_FILE || fail
/usr/bin/ionice -c2 -n7 rm -rf $TEMP_DIRECTORY &> $LOG_FILE || fail

echo "Compressed archive created."


