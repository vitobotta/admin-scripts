# admin-scripts #

Simple administration scripts I use on my servers. 

## Backups ##

### backup/duplicity.sh ###

Performs encrypted, incremental backups to a remote server using [duplicity](http://duplicity.nongnu.org). 
The first time it runs it creates the configuration file ~/.duplicity.config (in your home folder) with the following defaults:

``` bash
BACKUP_SOURCE_DIRECTORIES=(/home /root /var/www /var/log /etc /usr/local)
BACKUP_USER=your current username
BACKUP_HOST=(left blank)
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
```

These settings should be self-explanatory - you'll need to customise the settings in this file according to your needs. Note that you can configure the script so that it runs other scripts (for example for backing up databases) before or after duplicity backup. 

Usage is simple, just run

``` bash
duplicity.sh [incr|full] 
```

where the single argument determines whether you want to perform a full or incremental backup. 


### backup/xtrabackup.sh ###


Performs backups of MySQL databases using [Percona's xtrabackup](http://www.percona.com/doc/percona-xtrabackup/). xtrabackup allows for faster, safe backups and restores than mysqldump while databases are in use. For more information, please check out [this blog post](http://vitobotta.com/painless-hot-backups-mysql-live-databases-percona-xtrabackup/ "Painless, ultra fast hot backups and restores of MySQL databases with Percona's XtraBackup").

On the first run, the script creates the configuration file ~/.xtrabackup.config (in your home folder) with the following defaults:

``` bash
MYSQL_USER=your current MySQL username
MYSQL_PASS=(left blank)
MYSQL_DATA_DIR=/var/lib/mysql/
BACKUPS_DIRECTORY=$HOME/mysql-backups
MAX_BACKUP_CHAINS=3
```

You'll need to customise them accordingly to your needs.

Usage is simple, just run

``` bash
xtrabackup.sh [incr|full] 
```

where the single argument determines whether you want to perform a full or incremental backup. If running an incremental backup but no previous backups are found in the target directory, a full backup is performed instead.

Backups are stored with the following folder structure:

``` bash
├── full
│   ├── 2012-08-04_15-54-23
│   └── 2012-08-04_15-59-29
└── incr
    ├── 2012-08-04_15-55-01
    └── 2012-08-04_15-56-44
```

Each folder has a file named *backup.chain* that contains all the folders (full + incrementals) that belong to that backup chain/set. This is useful when restoring from an incremental.

**TODO**: support for automated restores. For the time being, please check [this blog post](http://vitobotta.com/painless-hot-backups-mysql-live-databases-percona-xtrabackup/ "Painless, ultra fast hot backups and restores of MySQL databases with Percona's XtraBackup") on restoring full backups, and [this page](http://www.percona.com/doc/percona-xtrabackup/xtrabackup_bin/incremental_backups.html?id=percona-xtrabackup:xtrabackup:incremental) on the Percona website on how to restore from incrementals.