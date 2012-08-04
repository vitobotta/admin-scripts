#!/bin/bash

die () {
	echo 1>&2 "$@"
	exit 1
}

INNOBACKUPEX=$(which innobackupex)
[ -f "$INNOBACKUPEX" ] || die "innobackupex script not found - please ensure xtrabackup is installed before proceeding."

CONFIG_FILE=$HOME/.xtrabackup.config

if [ -f $CONFIG_FILE ]; then
	echo -e "Loading configuration from $CONFIG_FILE."
	source $CONFIG_FILE
else
cat << EOF > $CONFIG_FILE
MYSQL_USER="$(whoami)"
MYSQL_PASS=
MYSQL_DATA_DIR=/var/lib/mysql/
BACKUPS_DIRECTORY=$HOME/mysql-backups
MAX_BACKUP_CHAINS=3
EOF

	die "Configuration has been initialised in $CONFIG_FILE. \nPlease make sure all settings are correctly defined/customised - aborting."
fi

[ -d $MYSQL_DATA_DIR ] || die "Please ensure the MYSQL_DATA_DIR setting in the configuration file points to the directory containing the MySQL databases."
[ -n "$MYSQL_USER" -a -n "$MYSQL_PASS" ] || die "Please ensure MySQL username and password are properly set in the configuration file."

FULLS_DIRECTORY=$BACKUPS_DIRECTORY/full
INCREMENTALS_DIRECTORY=$BACKUPS_DIRECTORY/incr

mkdir -vp $FULLS_DIRECTORY
mkdir -vp $INCREMENTALS_DIRECTORY

if [ "$1" = "full" ]; then
	$INNOBACKUPEX --slave-info --user="$MYSQL_USER" --password="$MYSQL_PASS" "$FULLS_DIRECTORY"

	NEW_BACKUP_DIR=$(find $FULLS_DIRECTORY -mindepth 1 -maxdepth 1 -type d -exec ls -dt {} \+ | head -1)

	echo $NEW_BACKUP_DIR > $NEW_BACKUP_DIR/backup.chain

elif [ "$1" = "incr" ]; then
	LAST_CHECKPOINTS=$(find "$FULLS_DIRECTORY"/../ -mindepth 3 -maxdepth 3 -type f -name xtrabackup_checkpoints -exec ls -dt {} \+ | head -1)
	LAST_BACKUP=${LAST_CHECKPOINTS%/xtrabackup_checkpoints}

	$INNOBACKUPEX --slave-info --user="$MYSQL_USER" --password="$MYSQL_PASS" --incremental --incremental-basedir="$LAST_BACKUP" "$INCREMENTALS_DIRECTORY"

	NEW_BACKUP_DIR=$(find $INCREMENTALS_DIRECTORY -mindepth 1 -maxdepth 1 -type d -exec ls -dt {} \+ | head -1)
	cp $LAST_BACKUP/backup.chain $NEW_BACKUP_DIR/
	echo $NEW_BACKUP_DIR >> $NEW_BACKUP_DIR/backup.chain

else
  die "Backup type not specified. Please run: as $0 [incr|full]"
fi

BACKUP_CHAINS=`ls $FULLS_DIRECTORY | wc -l`

if [[ $BACKUP_CHAINS -gt $MAX_BACKUP_CHAINS ]]; then
	CHAINS_TO_DELETE=$(expr $BACKUP_CHAINS - $MAX_BACKUP_CHAINS)
	
	for FULL_BACKUP in `ls $FULLS_DIRECTORY -t |  tail -n $CHAINS_TO_DELETE`; do
		grep -l $FULLS_DIRECTORY/$FULL_BACKUP $INCREMENTALS_DIRECTORY/**/backup.chain | while read incremental; do rm -rf "${incremental%/backup.chain}"; done
		rm -rf $FULLS_DIRECTORY/$FULL_BACKUP
	done
fi

unset MYSQL_USER
unset MYSQL_PASS
