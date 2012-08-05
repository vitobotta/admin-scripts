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

# Uncomment the following line to backup to a local directory or a locally mounted network share
# TARGET="file:///some/local/directory"

# Uncomment the following line to backup to a remote directory
# TARGET="rsync://user@host/destination-directory"

MAX_FULL_BACKUPS_TO_RETAIN=8
MAX_AGE_INCREMENTALS_TO_RETAIN=1W
MAX_AGE_CHAINS_TO_RETAIN=2M
MAX_VOLUME_SIZE=250

ENCRYPTION=1
PASSPHRASE= # used for ENCRYPT_KEY or, if this is not specified, for symmetric encryption

# Set ENCRYPT_KEY if you want to use GPG pub key encryption. Otherwise duplicity will just use symmetric encryption. 
# ENCRYPT_KEY=

# Optionally use a different key for signing
# SIGN_KEY=
# SIGN_KEY_PASSPHRASE=

COMPRESSION_LEVEL=6 # 0 disables compression

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

DUPLICITY_SETTINGS="--verbosity=${VERBOSITY-warning} --allow-source-mismatch --volsize=$MAX_VOLUME_SIZE"

if [[ $ENCRYPTION -eq 1 ]]; then
	[ -n "$ENCRYPT_KEY" ] && DUPLICITY_SETTINGS="$DUPLICITY_SETTINGS --encrypt-key=$ENCRYPT_KEY"
	[ -n "$SIGN_KEY" ] && DUPLICITY_SETTINGS="$DUPLICITY_SETTINGS --sign-key=$SIGN_KEY"
	# --gpg-options='--compress-algo=bzip2'
	#  --gpg-options='--compress-algo=bzip2'
else
	# export GZIP="-1"
	DUPLICITY_SETTINGS="$DUPLICITY_SETTINGS --no-encryption"
fi


DUPLICITY_COMMAND="$(which nice) -n 15 $IONICE_COMMAND duplicity $DUPLICITY_SETTINGS"

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


( 
  [ -n "$PASSPHRASE" ] && export PASSPHRASE=$PASSPHRASE
	[ -n "$SIGN_KEY_PASSPHRASE" ] && export SIGN_PASSPHRASE=$SIGN_KEY_PASSPHRASE

  if [ "$1" = "full" ]; then
    $DUPLICITY_COMMAND full $INCLUDE --exclude='**' --asynchronous-upload / $TARGET
  elif [ "$1" = "incr" ]; then
  	$DUPLICITY_COMMAND incr --full-if-older-than=$MAX_AGE_INCREMENTALS_TO_RETAIN $INCLUDE --exclude='**' --asynchronous-upload / $TARGET
  else
    die "Backup type not specified. Please run: as $0 [incr|full]"
  fi

	$DUPLICITY_COMMAND remove-all-but-n-full $MAX_FULL_BACKUPS_TO_RETAIN $TARGET --force
	$DUPLICITY_COMMAND remove-older-than $MAX_AGE_CHAINS_TO_RETAIN $TARGET --force
	$DUPLICITY_COMMAND cleanup --extra-clean --force $TARGET
	$DUPLICITY_COMMAND collection-status $TARGET

	unset DUPLICITY_PASSPHRASE
	unset SIGN_PASSPHRASE
	unset PASSPHRASE
)

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
