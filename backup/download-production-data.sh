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

if [ "$1" = "skip-download" ]; then
  ARCHIVE=`find ~/production-data.* -type f -exec ls -dt {} \+ | head -1 | rev | cut -d '/' -f 1 | rev`

  echo "Restoring MySQL datadir from $ARCHIVE..."
else
  shuffle

  DB_NODE="${DB_NODES[0]}"

  echo "*** Using node: $DB_NODE ***"

  ARCHIVE=`ssh -T $DB_NODE "find /backup/mysql/archives/ -type f -exec ls -dt {} \+ | head -1 | rev | cut -d '/' -f 1 | rev"`


  echo "Downloading latest archive available on $DB_NODE..."

  scp $DB_NODE:"/backup/mysql/archives/$ARCHIVE" $HOME/

  echo <<\EOF
  ...done. A copy of the archive as downloaded from the server is available as $HOME/$ARCHIVE.
  Should this restore fails, you can still use that archive manually without having to download the same archive again.

  Replacing the current MySQL datadir with the new one (if this fails, it may mean MySQL isn't running)...
EOF

fi

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
