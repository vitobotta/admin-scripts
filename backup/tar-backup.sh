#!/bin/bash

# A simple backup (full/incrementals) with tar

### Configuration ###

# Optionally, create the ~/.tar-backup.conf with the configuration settings.

BACKUP_ROOT="/home"
BACKUP_DESTINATION="/backups/"
EXCLUDE_LIST=( "/etc/scripts/shared" )
MAX_SETS=5 # e.g. 8 weekly full backups, and the rest incrementals

################################
# Do not edit below This Line  # 
################################

# Loading the configuration file, if present
if [[ -e ~/.tar-backup.conf ]];then
    source ~/.tar-backup.conf
fi

TAR="$(which tar)"

if [ ! -x "$TAR" ]; then
  echo "ERROR: tar not available ?!" >&2
  exit 1
fi

DEFAULT_EXCLUDE_LIST=( "/proc" "/mnt" "/sys" "/dev" "/lost+found" "/media" )

for exclude in ${DEFAULT_EXCLUDE_LIST[@]}
do
	TMP=" --exclude="$exclude
	EXCLUDE=$EXCLUDE$TMP
done

for exclude in ${EXCLUDE_LIST[@]}
do
	TMP=" --exclude="$exclude
	EXCLUDE=$EXCLUDE$TMP
done


EXCLUDE=$EXCLUDE" --exclude="$BACKUP_DESTINATION
TIMESTAMP=`date +%Y%m%d%H%M%S`

if [ "$1" = "--full" ]; then
	CREATE_FULL_BACKUP="1"
	
elif [ "$1" = "--incremental" ]; then
	LAST_FULL_BACKUP=`ls -1t $BACKUP_DESTINATION/*/full* 2>/dev/null | head -n 1`

	if [ "$LAST_FULL_BACKUP" = "" ]; then
		CREATE_FULL_BACKUP="1"
	else
		BACKUP_FOLDER="$( cd "$( dirname $LAST_FULL_BACKUP )" && pwd )"
		BACKUP_FILE="$BACKUP_FOLDER/incremental-$TIMESTAMP.tgz"
		SNAR=`ls $BACKUP_FOLDER/*.snar 2>/dev/null | head -n 1`
		
		if [ "$SNAR" = "" ]; then
				echo "ERROR: the file with information on the backup set is missing. The existing backup might be unusable :("
				echo "It is recommended to make a full backup with the --full option."
				exit 1
		fi
	fi

else 
		echo "tar-backup - Usage: " 
		echo "	1. Full backup: starts a new backup set."
		echo "	   ${BASH_SOURCE} --full 'description of the backup (optional)'"
		echo
		echo "	2. Incrementail backup: updates the last backup set; only the changes since the last backup in that set will be backed up."
		echo "	   ${BASH_SOURCE} --incremental 'description of the backup (optional)'"
		echo
		exit 1
fi

if [ "$CREATE_FULL_BACKUP" = "1" ]; then
	BACKUP_FOLDER="$BACKUP_DESTINATION/$TIMESTAMP"
	BACKUP_FILE="$BACKUP_FOLDER/full-$TIMESTAMP.tgz"
	SNAR="$BACKUP_FOLDER/backup-set.snar"
fi

LOG="$BACKUP_FOLDER/last-backup.log"

echo "Backing up $BACKUP_ROOT to $BACKUP_FILE ..."
echo

mkdir -p $BACKUP_FOLDER && $TAR -cpzf $BACKUP_FILE -g $SNAR $EXCLUDE $BACKUP_ROOT > $LOG

AVAILABLE_BACKUPS_INFO=$BACKUP_FOLDER/description

[ ! -f $AVAILABLE_BACKUPS_INFO ] && touch $AVAILABLE_BACKUPS_INFO
mv $AVAILABLE_BACKUPS_INFO $AVAILABLE_BACKUPS_INFO.tmp
[ "$2" != "" ] && echo "$BACKUP_FILE => $2" | cat - $AVAILABLE_BACKUPS_INFO.tmp > $AVAILABLE_BACKUPS_INFO
rm $AVAILABLE_BACKUPS_INFO.tmp

echo 
echo "...done"
echo
echo

while [[ `ls $BACKUP_DESTINATION/*/full* 2>/dev/null | wc -l` -gt $MAX_SETS ]]; 
do
	OLDEST_BACKUP_SET=`ls -1tr $BACKUP_DESTINATION/*/full* 2>/dev/null | head -n 1`

	if [ "$OLDEST_BACKUP_SET" != "" ]; then
		OLDEST_BACKUP_FOLDER="$( cd "$( dirname $OLDEST_BACKUP_SET )" && pwd )"
		rm -rf $OLDEST_BACKUP_FOLDER && echo "Deleted older backup set $OLDEST_BACKUP_FOLDER"
	fi
done
