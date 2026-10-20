# Database backup script for the mysql-8.4 stack.
# Dumps a single database (or one table) with mysqldump using the defaults
# file passed via -c.
#
# Usage: backup.sh -c my.cnf -d [database] [-t table]
#
# The output is a gzip-compressed SQL dump named
# <database>[_<table>]_<timestamp>.sql.gz in the current directory.
# Restore with: gunzip -c <dump>.sql.gz | mysql -u root -p <database>
