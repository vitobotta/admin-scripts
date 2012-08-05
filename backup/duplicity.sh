#!/bin/bash

die () {
	echo -e 1>&2 "$@"
	exit 1
}

DUPLICITY=$(which duplicity)
[ -f "$DUPLICITY" ] || die "Duplicity not found - please ensure it is installed before proceeding."

ENCRYPTION=1
COMPRESSION_LEVEL=6


CONFIG_FILE=$HOME/.duplicity.config

if [ -f $CONFIG_FILE ]; then
	echo -e "Loading configuration from $CONFIG_FILE."
	source $CONFIG_FILE
else
cat << EOF > $CONFIG_FILE
INCLUDE=(/home /root /var/www /var/log /etc /usr/local)

# Uncomment and set the following to backup to a local directory or a locally mounted network share
# TARGET="file:///some/local/directory"

# Uncomment and set the following to backup to a remote directory
# TARGET="rsync://user@host/destination-directory"

MAX_FULL_BACKUPS_TO_RETAIN=8
MAX_AGE_INCREMENTALS_TO_RETAIN=1W
MAX_AGE_CHAINS_TO_RETAIN=2M
MAX_VOLUME_SIZE=25

ENCRYPTION=1
PASSPHRASE= # used for ENCRYPT_KEY or, if this is not specified, for symmetric encryption

# Set ENCRYPT_KEY if you want to use GPG pub key encryption. Otherwise duplicity will just use symmetric encryption. 
# ENCRYPT_KEY=

# Optionally use a different key for signing
# SIGN_KEY=
# SIGN_KEY_PASSPHRASE=

COMPRESSION_LEVEL=6 # 1-9; 0 disables compression; it currently works only if encryption is enabled

VERBOSITY=4 # 0 Error, 2 Warning, 4 Notice (default), 8 Info, 9 Debug (noisiest)

# Comment out the following if you want to run one or more scripts before duplicity backup.
#RUN_BEFORE=(/some/script /another/script)

# Comment out the following if you want to run one or more scripts after duplicity backup.
#RUN_AFTER=(/some/script /another/script)
EOF

	die "Configuration has been initialised in $CONFIG_FILE. \nPlease make sure all settings are correctly defined/customised - aborting."
fi

[ ${#INCLUDE[@]} -gt 0 ] || die "Please set which directories you want to backup (setting 'INCLUDE' in the configuration file)."
[ -n "$TARGET" ] || die "Please set the destination directory that will contain your backups (setting 'TARGET' in the configuration file)."

IONICE=$(which ionice)

if [ -n "$IONICE" ]; then
	IONICE_COMMAND="$IONICE -c2 -n7"
fi

INCLUDE="$(for s in ${INCLUDE[@]} ; do echo --include=$s; done)"

BACKUP_SETTINGS="--verbosity=$VERBOSITY --allow-source-mismatch --volsize=$MAX_VOLUME_SIZE $INCLUDE --exclude=** --asynchronous-upload / $TARGET"

if [[ $ENCRYPTION -eq 1 ]]; then
	[ -n "$ENCRYPT_KEY" ] && BACKUP_SETTINGS="$BACKUP_SETTINGS --encrypt-key=$ENCRYPT_KEY"
	[ -n "$SIGN_KEY" ] && BACKUP_SETTINGS="$BACKUP_SETTINGS --sign-key=$SIGN_KEY"
	
	BACKUP_SETTINGS="--gpg-options=-z$COMPRESSION_LEVEL $BACKUP_SETTINGS"
else
	# export GZIP="-1"
	BACKUP_SETTINGS=" $BACKUP_SETTINGS"
fi

DUPLICITY="$(which nice) -n 15 $IONICE_COMMAND $DUPLICITY"

if [ ${#RUN_BEFORE[@]} -gt 0 ]; then
	echo -e "Running 'before' scripts...\n"
	for SCRIPT in ${RUN_BEFORE[@]}; do
		if [ -f $SCRIPT ]; then
			$SCRIPT "$@"
		else
			echo "WARNING: before script $SCRIPT not found"
		fi
	done
	echo
fi

[ -n "$PASSPHRASE" ] && export PASSPHRASE=$PASSPHRASE
[ -n "$SIGN_KEY_PASSPHRASE" ] && export SIGN_PASSPHRASE=$SIGN_KEY_PASSPHRASE

if [ "$1" = "full" ]; then
  $DUPLICITY full $BACKUP_SETTINGS 
elif [ "$1" = "incr" ]; then
	$DUPLICITY incr --full-if-older-than=$MAX_AGE_INCREMENTALS_TO_RETAIN $BACKUP_SETTINGS 
else
  die "Backup type not specified. Please run: as $0 [incr|full]"
fi

$DUPLICITY remove-all-but-n-full $MAX_FULL_BACKUPS_TO_RETAIN $TARGET --force
$DUPLICITY remove-older-than $MAX_AGE_CHAINS_TO_RETAIN $TARGET --force
$DUPLICITY cleanup --extra-clean --force $TARGET
$DUPLICITY collection-status $TARGET

unset DUPLICITY_PASSPHRASE
unset SIGN_PASSPHRASE
unset PASSPHRASE

if [ ${#RUN_AFTER[@]} -gt 0 ]; then
	echo -e "Running 'after' scripts...\n"
	for SCRIPT in ${RUN_AFTER[@]}; do
		if [ -f $SCRIPT ]; then
			$SCRIPT "$@"
		else
			echo "WARNING: before script $SCRIPT not found"
		fi
	done
	echo
fi
