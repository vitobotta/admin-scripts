This repository contains simple administration scripts I use on my servers. 

# Backups 

- [duplicity.sh](admin-scripts/wiki/duplicity.sh): Performs encrypted, incremental backups of the specified directories to a remote server using [duplicity](http://duplicity.nongnu.org).

- [xtrabackup.sh](admin-scripts/wiki/xtrabackup.sh): Performs backups of MySQL databases using [Percona's xtrabackup](http://www.percona.com/doc/percona-xtrabackup/). xtrabackup allows for faster, safe backups and restores than mysqldump while databases are in use. For more information, please check out [this blog post](http://vitobotta.com/painless-hot-backups-mysql-live-databases-percona-xtrabackup/ "Painless, ultra fast hot backups and restores of MySQL databases with Percona's XtraBackup").
