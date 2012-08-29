#!/bin/bash

DB_NODES=(db1 db2 db3)

die () {
	echo -e 1>&2 "$@"
	exit 1
}

shuffle() {
   local i tmp size max rand

   # $RANDOM % (i+1) is biased because of the limited range of $RANDOM
   # Compensate by using a range which is a multiple of the DB_NODES size.
   size=${#DB_NODES[*]}
   max=$(( 32768 / size * size ))

   for ((i=size-1; i>0; i--)); do
      while (( (rand=$RANDOM) >= max )); do :; done
      rand=$(( rand % (i+1) ))
      tmp=${DB_NODES[i]} DB_NODES[i]=${DB_NODES[rand]} DB_NODES[rand]=$tmp
   done
}

shuffle

DB_NODE="${DB_NODES[0]}"

echo "*** Using node: $DB_NODE ***"

ssh $DB_NODE  <<\EOF
  LOG_FILE="/tmp/production-data-restore-$(date +%Y-%m-%d-%H.%M.%S).log"
  echo "" > $LOG_FILE

  die () {
    echo -e 1>&2 "$@"
    exit 1
  }

  fail () {
    die "...FAILED! See $LOG_FILE for details - aborting.\n"
  }

  echo "Preparing copy of the latest full backup..."

  LATEST_FULL_BACKUP=`find /backup/mysql/full/ -mindepth 1 -maxdepth 1 -type d -exec ls -dt {} \+ | head -1`
  TEMP_DIRECTORY=`mktemp -d`

  rsync --quiet --delete -zarv $LATEST_FULL_BACKUP/ $TEMP_DIRECTORY/ &> $LOG_FILE || fail

  echo "Prepared a copy of the data."
  echo "Finalising the copy for use with MySQL server..."

  innobackupex-1.5.1 --apply-log --ibbackup=xtrabackup_51 $TEMP_DIRECTORY/ &> $LOG_FILE || fail

  echo "Copy of the data finalised for use with MySQL server."
  echo "Creating a compressed archive..."

  ARCHIVE="/tmp/production-data.tgz"

  [ -f $ARCHIVE ] && rm $ARCHIVE

  GZIP=-9 tar cvfz $ARCHIVE $TEMP_DIRECTORY &> $LOG_FILE || fail
  rm -rf $TEMP_DIRECTORY &> $LOG_FILE || fail

  echo "Compressed archive created."
EOF


echo "Downloading..."

ARCHIVE="/tmp/production-data.tgz"

[ -f $ARCHIVE ] && rm $ARCHIVE

scp $DB_NODE:$ARCHIVE /tmp/

echo "...done."

echo "Replacing the current datadir with the new one..."

MYSQL_DATA_DIR=`mysql -uroot -p$MYSQL_PWD -Ns -e "show variables like 'datadir'" | cut -f 2`

# Remove trailing slash
MYSQL_DATA_DIR=`echo "${MYSQL_DATA_DIR}" | sed -e "s/\/*$//" `

[ -d $MYSQL_DATA_DIR ] || die "Uhm...can't find MySQL datadir"

if [[ `uname -s` = "Darwin" ]]; then
  # Assuming MySQL/Percona has been installed with homebrew...
  MYSQL_STOP_COMMAND="mysql.server stop"
  MYSQL_START_COMMAND="mysql.server start"
else
  MYSQL_STOP_COMMAND="service mysql stop"
  MYSQL_START_COMMAND="service mysql start"
fi

(
  $MYSQL_STOP_COMMAND
  
  mv $MYSQL_DATA_DIR{,.$(date +%Y-%m-%d-%H-%M-%S)}
  
  mkdir $MYSQL_DATA_DIR && cd $MYSQL_DATA_DIR 
  
  tar xvfz $ARCHIVE 
  
  mv tmp/tmp*/* . 

  [[ `uname -s` = "Linux" ]] && chown -R mysql:mysql .
  
  $MYSQL_START_COMMAND

)
