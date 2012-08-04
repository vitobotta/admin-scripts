#!/bin/bash

die () {
	echo -e 1>&2 "$@"
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
MAX_BACKUP_CHAINS=8
EOF

	die "Configuration has been initialised in $CONFIG_FILE. \nPlease make sure all settings are correctly defined/customised - aborting."
fi

[ -d $MYSQL_DATA_DIR ] || die "Please ensure the MYSQL_DATA_DIR setting in the configuration file points to the directory containing the MySQL databases."
[ -n "$MYSQL_USER" -a -n "$MYSQL_PASS" ] || die "Please ensure MySQL username and password are properly set in the configuration file."

FULLS_DIRECTORY=$BACKUPS_DIRECTORY/full
INCREMENTALS_DIRECTORY=$BACKUPS_DIRECTORY/incr
LOGS="/var/log/xtrabackup"


mkdir -vp $FULLS_DIRECTORY
mkdir -vp $INCREMENTALS_DIRECTORY
mkdir -vp $LOGS

IONICE=$(which ionice)

if [ -n "$IONICE" ]; then
	IONICE_COMMAND="$IONICE -c2 -n7"
fi

INNOBACKUPEX_COMMAND="$(which nice) -n 15 $IONICE_COMMAND $INNOBACKUPEX"
RSYNC_COMMAND="$(which nice) -n 15 $IONICE_COMMAND  $(which rsync)"

full_backup () {
	$INNOBACKUPEX_COMMAND --slave-info --user="$MYSQL_USER" --password="$MYSQL_PASS" "$FULLS_DIRECTORY"

	NEW_BACKUP_DIR=$(find $FULLS_DIRECTORY -mindepth 1 -maxdepth 1 -type d -exec ls -dt {} \+ | head -1)

	echo $NEW_BACKUP_DIR > $NEW_BACKUP_DIR/backup.chain
}

incremental_backup () {
	LAST_BACKUP=${LAST_CHECKPOINTS%/xtrabackup_checkpoints}

	$INNOBACKUPEX_COMMAND --slave-info --user="$MYSQL_USER" --password="$MYSQL_PASS" --incremental --incremental-basedir="$LAST_BACKUP" "$INCREMENTALS_DIRECTORY"

	NEW_BACKUP_DIR=$(find $INCREMENTALS_DIRECTORY -mindepth 1 -maxdepth 1 -type d -exec ls -dt {} \+ | head -1)
	cp $LAST_BACKUP/backup.chain $NEW_BACKUP_DIR/
	echo $NEW_BACKUP_DIR >> $NEW_BACKUP_DIR/backup.chain
}


if [ "$1" = "full" ]; then
	full_backup
elif [ "$1" = "incr" ]; then
	LAST_CHECKPOINTS=$(find $BACKUPS_DIRECTORY -mindepth 3 -maxdepth 3 -type f -name xtrabackup_checkpoints -exec ls -dt {} \+ | head -1)
	
	if [[ -f $LAST_CHECKPOINTS ]]; then
		incremental_backup
	else
		full_backup
	fi
elif [ "$1" = "list" ]; then
	if [[ -d $FULLS_DIRECTORY ]]; then
		BACKUP_CHAINS=$(ls $FULLS_DIRECTORY | wc -l)
	else
		BACKUP_CHAINS=0
	fi
		
	if [[ $BACKUP_CHAINS -gt 0 ]]; then
		echo -e "Available backup chains (from oldest to latest):\n"

		for FULL_BACKUP in `ls $FULLS_DIRECTORY -tr`; do
			let COUNTER=COUNTER+1

			echo "Backup chain $COUNTER:"
			echo -e "\tFull:        $FULL_BACKUP"

			if [[ $(ls $INCREMENTALS_DIRECTORY | wc -l) -gt 0 ]]; then
				grep -l $FULL_BACKUP $INCREMENTALS_DIRECTORY/**/backup.chain | \
				while read INCREMENTAL; 
				do 
					BACKUP_DATE=${INCREMENTAL%/backup.chain}
					echo -e "\tIncremental: ${BACKUP_DATE##*/}"
				done
			fi
		done
		
		LATEST_BACKUP=$(find $BACKUPS_DIRECTORY -mindepth 2 -maxdepth 2 -type d -exec ls -dt {} \+ | head -1)
		
		[[ "$LATEST_BACKUP" == *full* ]] && IS_FULL=1 || IS_FULL=0

		BACKUP_DATE=${LATEST_BACKUP##*/}

		if [[ "$LATEST_BACKUP" == *full* ]]
		then
		  echo -e "\nLatest backup available:\n\tFull: $BACKUP_DATE"
		else
		  echo -e "\nLatest backup available:\n\tIncremental: $BACKUP_DATE"
		fi
		
		exit 1
	else
		die "No backup chains available in the backup directory specified in the configuration ($BACKUPS_DIRECTORY)"
	fi
elif [ "$1" = "restore" ]; then
	([ -n "$2" ] && [ -n "$3" ]) || die "Missing arguments. Please run as: \n\t$0 restore <timestamp> <destination folder>\nTo see the list of the available backups, run:\n\t$0 list"
		
	BACKUP_TIMESTAMP="$2"
	DESTINATION="$3"
	BACKUP=`find $BACKUPS_DIRECTORY -mindepth 2 -maxdepth 2 -type d -name $BACKUP_TIMESTAMP -exec ls -dt {} \+ | head -1`
	LOG_FILE="$LOGS/restore-$BACKUP_TIMESTAMP.log"
	
	echo "" > $LOG_FILE
	
	(mkdir -vp $DESTINATION) || die "Could not access destination folder $3 - aborting"
	
	if [[ -d "$BACKUP" ]]; then
		echo -e "!! About to restore MySQL backup taken on $BACKUP_TIMESTAMP to $DESTINATION !!\n"
		
		if [[ "$BACKUP" == *full* ]]; then
			(
				echo "- Restore of full backup taken on $BACKUP_TIMESTAMP"

				echo "Copying data files to destination..."
				$RSYNC_COMMAND --quiet -ah --delete $BACKUP/ $DESTINATION &> $LOG_FILE
				echo -e "...done.\n"
			
				echo "Preparing the destination for use with MySQL..."
				$INNOBACKUPEX_COMMAND --apply-log --ibbackup=xtrabackup_51 $DESTINATION  &> $LOG_FILE
				echo -e "...done.\n"
			) || die "...FAILED! See $LOG_FILE for details - aborting."

		else
			(
				XTRABACKUP=$(which xtrabackup)
				[ -f "$XTRABACKUP" ] || die "xtrabackup executable not found - this is required in order to restore from incrementals. Ensure xtrabackup is installed properly - aborting."
			
				FULL_BACKUP=$(cat $BACKUP/backup.chain | head -1)
			
				echo "- Restore of base backup from $FULL_BACKUP"

				echo "Copying data files to destination..."
				$RSYNC_COMMAND --quiet -ah --delete $FULL_BACKUP/ $DESTINATION  &> $LOG_FILE
				echo -e "...done.\n"

				echo "Preparing the base backup in the destination..."
				$XTRABACKUP --prepare --apply-log-only --target-dir=$DESTINATION  &> $LOG_FILE
				echo -e "...done.\n"
			
				for INCREMENTAL in $(cat $BACKUP/backup.chain | tail -n +2); do
					echo -e "Applying incremental from $INCREMENTAL...\n"
					$XTRABACKUP  --prepare --apply-log-only --target-dir=$DESTINATION --incremental-dir=$INCREMENTAL  &> $LOG_FILE
					echo -e "...done.\n"
				done

				echo "Finalising the destination..."
				$XTRABACKUP --prepare --target-dir=$DESTINATION  &> $LOG_FILE
				echo -e "...done.\n"
			)  || die "...FAILED! See $LOG_FILE for details - aborting."

		fi
		
		rm $LOG_FILE # no errors, no need to keep it
		
		echo -e "The destination is ready. All you need to do now is:
		- ensure the MySQL user owns the destination directory, e.g.: chown -R mysql:mysql $DESTINATION
		- stop MySQL server
		- replace the content of the MySQL datadir (usually /var/lib/mysql) with the content of $DESTINATION
		- start MySQL server again"
	else
		die "Backup not found. To see the list of the available backups, run: $0 list"
	fi
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
