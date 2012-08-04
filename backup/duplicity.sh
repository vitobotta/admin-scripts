#!/bin/bash

die () {
	echo 1>&2 "$@"
	exit 1
}

DUPLICITY=$(which duplicity)
[ ! -f "$DUPLICITY" ] && die "Duplicity not found - please ensure it is installed before proceeding."

CONFIG_FILE=$HOME/.duplicity.config

if [ -f $CONFIG_FILE ]; then
	echo "Loading configuration from $CONFIG_FILE."
	source $CONFIG_FILE
else
cat << EOF > $CONFIG_FILE
BACKUP_SOURCE_DIRECTORIES=(/home /root /var/www /var/log /etc /usr/local)
BACKUP_USER="$(whoami)"
BACKUP_HOST=
BACKUP_TARGET_DIRECTORY="duplicity/"
KEEP_FULL_BACKUPS=4
VERBOSITY=4
DUPLICITY_PASSPHRASE=
EOF

	die "Configuration has been initialised in $CONFIG_FILE. Please make sure all settings are correctly defined/customised - aborting."
fi

(
	[ -n "$BACKUP_USER" ] && \
	[ -n "$BACKUP_HOST" ] && \
	[ -n "$BACKUP_TARGET_DIRECTORY" ] && \
	[ -n "$DUPLICITY_PASSPHRASE" ]
) || die "Please ensure all the settings are defined in the configuration file ($HOME/.duplicity.config)."

BACKUP_TARGET_DIRECTORY=$BACKUP_TARGET_DIRECTORY/$(hostname)
TARGET="rsync://$BACKUP_USER@$BACKUP_HOST/$BACKUP_TARGET_DIRECTORY"
INCLUDE="$(for s in ${BACKUP_SOURCE_DIRECTORIES[@]} ; do echo --include=$s; done)"
DUPLICITY_SETTINGS="--verbosity=${VERBOSITY-warning} --archive=/tmp/duplicity --allow-source-mismatch"
DUPLICITY_COMMAND="$(which nice) -n 15 $(which ionice) -c2 -n7 duplicity $DUPLICITY_SETTINGS"

ssh $BACKUP_USER@$BACKUP_HOST mkdir -vp $BACKUP_TARGET_DIRECTORY

( 
  export PASSPHRASE=$DUPLICITY_PASSPHRASE

  if [ "$1" = "full" ]; then
    $DUPLICITY_COMMAND full $INCLUDE --exclude='**' --asynchronous-upload / $TARGET
  elif [ "$1" = "incr" ]; then
    $DUPLICITY_COMMAND incr $INCLUDE --exclude='**' --asynchronous-upload / $TARGET
  else
    die "Periodicity not specified: Please run: as $0 [incr|full]"
  fi

  $DUPLICITY_COMMAND remove-all-but-n-full $KEEP_FULL_BACKUPS $TARGET --force
	$DUPLICITY_COMMAND cleanup --extra-clean --force $TARGET
  $DUPLICITY_COMMAND collection-status $TARGET

	unset DUPLICITY_PASSPHRASE
	unset PASSPHRASE
)
