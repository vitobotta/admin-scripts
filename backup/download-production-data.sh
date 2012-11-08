#!/bin/bash

# ---------------------------------------------------------------------------------------------
# Just a script I use sometimes to download production data to my dev machine for testing etc
# with real data.
# ---------------------------------------------------------------------------------------------

set -e

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

ARCHIVE="production-data.$(date +%Y-%m-%d-%H.%M.%S).tgz"

ssh -T $DB_NODE "echo $ARCHIVE > /tmp/production-data-archive-name"

ssh -T $DB_NODE <<\EOF
  set -e

  LOG_FILE="/tmp/production-data-restore-$(date +%Y-%m-%d-%H.%M.%S).log"
  echo "" > $LOG_FILE

  die () {
    echo -e 1>&2 "$@"
    exit 1
  }

  fail () {
    die "...FAILED! See $LOG_FILE for details - aborting.\n"
  }

  echo "Preparing copy of the latest backup available on $DB_NODE..."

  LAST_BACKUP_TIMESTAMP=`find /backup/mysql/ -mindepth 2 -maxdepth 2 -type d -exec ls -dt {} \+ | head -1 | rev | cut -d '/' -f 1 | rev`
  TEMP_DIRECTORY=`mktemp -d`

  /admin-scripts/backup/xtrabackup.sh restore $LAST_BACKUP_TIMESTAMP $TEMP_DIRECTORY

  echo "Prepared a copy of the data, now creating a compressed archive..."

  ARCHIVE="/tmp/`cat /tmp/production-data-archive-name`"

  /usr/bin/ionice -c2 -n7 tar cvfz $ARCHIVE $TEMP_DIRECTORY &> $LOG_FILE || fail
  /usr/bin/ionice -c2 -n7 rm -rf $TEMP_DIRECTORY &> $LOG_FILE || fail

  echo "Compressed archive created."
EOF


echo "Downloading..."

scp $DB_NODE:"/tmp/$ARCHIVE" $HOME/

echo <<\EOF
  ...done. A copy of the archive as downloaded from the server is available as $ARCHIVE.
  Should this restore fails, you can still use that archive manually without having to download the same archive again.

  Replacing the current MySQL datadir with the new one (if this fails, it may mean MySQL isn't running)...
EOF

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
  
  tar xvfz $HOME/$ARCHIVE 
  
  mv tmp/tmp*/* . 

  [[ `uname -s` = "Linux" ]] && chown -R mysql:mysql .
  
  $MYSQL_START_COMMAND
)
