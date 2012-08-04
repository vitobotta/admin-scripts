#!/bin/bash

die () {
	echo 1>&2 "$@"
	exit 1
}

DUPLICITY=$(which duplicity)
[ ! -f "$DUPLICITY" ] && die "Duplicity not found - please ensure it is installed before proceeding."


CONFIG_FILE=$HOME/.duplicity.config

if [ -f $CONFIG_FILE ]; then
	echo -e "Loading configuration from $CONFIG_FILE."
	source $CONFIG_FILE
else
cat << EOF > $CONFIG_FILE
BACKUP_SOURCE_DIRECTORIES=(/home /root /var/www /var/log /etc /usr/local)
BACKUP_USER="$(whoami)"
BACKUP_HOST=
BACKUP_TARGET_DIRECTORY="duplicity/"
MAX_FULL_BACKUPS=8
MAX_INCREMENTALS_AGE=1W
MAX_CHAIN_AGE=2M
MAX_VOLUME_SIZE=250
VERBOSITY=4 # 0 is total silent, 4 is the default, and 9 is noisiest
DUPLICITY_PASSPHRASE=

# Comment out the following if you want to run one or more scripts before duplicity backup.
#RUN_BEFORE=(/some/script /another/script)

# Comment out the following if you want to run one or more scripts after duplicity backup.
#RUN_AFTER=(/some/script /another/script)
EOF

	die "Configuration has been initialised in $CONFIG_FILE. \nPlease make sure all settings are correctly defined/customised - aborting."
fi

(
	[ -n "$BACKUP_USER" ] && \
	[ -n "$BACKUP_HOST" ] && \
	[ -n "$BACKUP_TARGET_DIRECTORY" ] && \
	[ -n "$DUPLICITY_PASSPHRASE" ]
) || die "Please ensure all the settings are defined in the configuration file ($HOME/.duplicity.config)."

IONICE=$(which ionice)

if [ -n "$IONICE" ]; then
	IONICE_COMMAND="$IONICE -c2 -n7"
fi

BACKUP_TARGET_DIRECTORY=$BACKUP_TARGET_DIRECTORY/$(hostname)
TARGET="rsync://$BACKUP_USER@$BACKUP_HOST/$BACKUP_TARGET_DIRECTORY"
INCLUDE="$(for s in ${BACKUP_SOURCE_DIRECTORIES[@]} ; do echo --include=$s; done)"
DUPLICITY_SETTINGS="--verbosity=${VERBOSITY-warning} --archive=/tmp/duplicity --allow-source-mismatch --volsize=$MAX_VOLUME_SIZE"
DUPLICITY_COMMAND="$(which nice) -n 15 $IONICE_COMMAND duplicity $DUPLICITY_SETTINGS"

if [ -n "$BACKUP_USER" ]; then
	echo -e "Running 'before' scripts...\n"
	for SCRIPT in ${RUN_BEFORE[@]}; do
		if [ -f $SCRIPT ]; then
			$SCRIPT
		else
			echo "WARNING: before script $SCRIPT not found"
		fi
	done
	echo
fi


ssh $BACKUP_USER@$BACKUP_HOST mkdir -vp $BACKUP_TARGET_DIRECTORY

( 
  export PASSPHRASE=$DUPLICITY_PASSPHRASE

  if [ "$1" = "full" ]; then
    $DUPLICITY_COMMAND full $INCLUDE --exclude='**' --asynchronous-upload / $TARGET
  elif [ "$1" = "incr" ]; then
  	$DUPLICITY_COMMAND incr --full-if-older-than=$MAX_INCREMENTALS_AGE $INCLUDE --exclude='**' --asynchronous-upload / $TARGET
  else
    die "Periodicity not specified. Please run: as $0 [incr|full]"
  fi

	$DUPLICITY_COMMAND remove-all-but-n-full $MAX_FULL_BACKUPS $TARGET --force
	$DUPLICITY_COMMAND remove-older-than $MAX_CHAIN_AGE $TARGET --force
	$DUPLICITY_COMMAND cleanup --extra-clean --force $TARGET
	$DUPLICITY_COMMAND collection-status $TARGET

	unset DUPLICITY_PASSPHRASE
	unset PASSPHRASE
)

if [ -n "$BACKUP_USER" ]; then
	echo -e "Running 'after' scripts...\n"
	for SCRIPT in ${RUN_AFTER[@]}; do
		if [ -f $SCRIPT ]; then
			$SCRIPT
		else
			echo "WARNING: before script $SCRIPT not found"
		fi
	done
	echo
fi
