#!/bin/bash

# Dieses Skript fuer das taegliche Backup auf dem Datenbank-Server des Stud.IP durch.
#
# ms, 20.09.2009

# Die Fehlermeldung werden an folgende Adressen gemeldet
v_arr_mailadressen=('michael.schaarschmidt@urz.uni-halle.de' \
                    'dirk.pollmaecher@urz.uni-halle.de' \
                    'kristina.haase@urz.uni-halle.de')

# Soll das Backup gleich auf den zentralen Archiv-Server verschoben werden?
ENABLE_ARCHIVING_BACKUP="TRUE"

# soll mysqlhotcopy fuer die Sicherung benutzt werden?
# wenn ja -> TRUE, wenn nein -> FALSE (default ist FALSE)
ENABLE_MYSQLHOTCOPY="TRUE"

# soll Stored Procedures, Stored Functions und Views gesichert werden?
# wenn ja -> TRUE, wenn nein -> FALSE (default ist FALSE)
ENABLE_VERSION5_EXTENSIONS="TRUE"

# soll mysqldump fuer die Sicherung benutzt werden?
# wenn ja -> TRUE, wenn nein -> FALSE (default ist FALSE)
ENABLE_MYSQLDUMP="FALSE"

date=`date +%Y%m%d_%H%M_$$`
DUMP_DIR_BASE="/archiv/backup"
DUMP_DIR="${DUMP_DIR_BASE}/$date"

# Wir holen das Passwort aus dem Verzeichnis des ausfuehrenden Nutzers
MYSQL_USER="root"
MYSQL_PASSWORD=
MYSQL_HOST="localhost"

if test -e $HOME/.password/mysql_${MYSQL_HOST}_${MYSQL_USER}
then
  source $HOME/.password/mysql_${MYSQL_HOST}_${MYSQL_USER}
  MYSQL_USER=$db_user
  MYSQL_PASSWORD=$db_password
else
  echo "Konnte die Passwort-Datei nicht finden oder oeffnen" | notify_admin "Allgemeines Problem"
fi


function notify_admin() # {{{
{
  for mailadresse in ${mailadressen[*]}
  do
    cat | mail -s "FEHLER bei Backup auf ${HOSTNAME} - $1" $mailadresse
  done
}  # }}}

function table_statistic() # {{{
{
  (
      echo "select UPDATE_TIME, TABLE_SCHEMA, TABLE_NAME, TABLE_TYPE"
      echo " from information_schema.tables"
      echo " where TABLE_SCHEMA != 'information_schema'"
      echo "  and  UPDATE_TIME > '2008-09-30'"
      echo " order by UPDATE_TIME desc, TABLE_SCHEMA, TABLE_NAME ;" 
  ) | \
      mysql \
          -h $MYSQL_HOST \
          -u $MYSQL_USER \
          --password=$MYSQL_PASSWORD
} # }}}

function dump_create_tables() # {{{
{
  local database=$1
  local dump_dir=$2
  local file=""

  local opts=""
#  if is_version_5
#  then
#    opts="$opts --routines"
#  fi

  get_tables $database >$dump_dir/all_tables.txt

  for table in `get_tables $database`
  do
    file=$dump_dir/create_table.$table.sql
    mysqldump -h $MYSQL_HOST \
              -u $MYSQL_USER \
              --password=$MYSQL_PASSWORD \
              --comments \
              --complete-insert \
              --create-options \
              --force \
              --quote-names \
              --hex-blob \
              --no-create-db \
              --no-data \
              --disable-keys \
              $opts \
              $database $table >$file
  done
} # }}}

function dump_table_data() # {{{
{
  local database=$1
  local dump_dir=$2
  local file=""

  for table in `get_tables $database`
  do
    file=$dump_dir/data.$table.sql
    mysqldump -h $MYSQL_HOST \
              -u $MYSQL_USER \
              --password=$MYSQL_PASSWORD \
              --complete-insert \
              --extended-insert=false \
              --force \
              --disable-keys \
              --hex-blob \
              --no-create-db \
              --no-create-info \
              --disable-keys \
              $database $table > $file
    gzip $file
  done
} # }}}

function dump_create_views() # {{{
{
  local database=$1
  local dump_dir=$2
  local file=""
  local views=`get_views $database`

  get_views $database >$dump_dir/all_views.txt

#  echo "-- Views der Database $database" >$file
  for v in $views
  do
    file=$dump_dir/create_view.$v.sql
    (
      echo "create view if not exists $v as "
      echo "select VIEW_DEFINITION from VIEWS" \
           " where TABLE_SCHEMA = '$database'" \
           "  and  TABLE_NAME   = '$v';" \
           | mysql --skip-column-names \
                   -h $MYSQL_HOST \
                   -u $MYSQL_USER \
                   --password=$MYSQL_PASSWORD \
                   information_schema 
      echo ";"
      echo ""
    ) >$file        

#    echo "SHOW CREATE VIEW $v;" \
#         | mysql --skip-column-names \
#                 -h $MYSQL_HOST \
#                 -u $MYSQL_USER \
#                 --password=$MYSQL_PASSWORD \
#                 $database \
#          >>$file        
  done
} # }}}

function dump_create_functions() # {{{
{
  local database=$1
  local dump_dir=$2
  local file=""
  local functions=`get_functions $database`

  get_functions $database >$dump_dir/all_functions.txt

  (
    mysqldump -h $MYSQL_HOST \
              -u $MYSQL_USER \
              --password=$MYSQL_PASSWORD \
              --force \
              --no-create-db \
              --no-create-info \
              --no-data \
              --routines \
              $database
  ) >$dump_dir/create_functions.sql

  for f in $functions
  do
    file=$dump_dir/create_function.$f.sql
    (
      echo "SHOW CREATE FUNCTION $f;" \
         | mysql --skip-column-names --xml \
                 -h $MYSQL_HOST \
                 -u $MYSQL_USER \
                 --password=$MYSQL_PASSWORD \
                 $database \
    ) >$file        
  done
} # }}}

function dump_create_procedures() # {{{
{
  local database=$1
  local dump_dir=$2
  local file=""
  local procedures=`get_procedures $database`

  get_procedures $database >$dump_dir/all_procedures.txt

  for p in $procedures
  do
    file=$dump_dir/create_procedures.$p.sql
    (
      echo "SHOW CREATE FUNCTION $p;" \
         | mysql --skip-column-names --xml \
                 -h $MYSQL_HOST \
                 -u $MYSQL_USER \
                 --password=$MYSQL_PASSWORD \
                 $database \
    ) >$file        
  done
} # }}}

function get_tables() # {{{
{
  local database=$1

  if is_version_5
  then
    (
      echo "select TABLE_NAME"
      echo " from  information_schema.TABLES"
      echo " WHERE TABLE_SCHEMA = '$database'" 
      echo " and    TABLE_TYPE = 'BASE TABLE'" 
      echo " order by TABLE_NAME"
      echo ";" 
    ) | \
      mysql --skip-column-names \
                -h $MYSQL_HOST \
                -u $MYSQL_USER \
                --password=$MYSQL_PASSWORD \
                information_schema
  else
    local views=`get_views $database`
    local ignore="viw$"

    for v in $views
    do
      ignore="$ignore\|$v"
    done

    echo "show tables;" \
        | mysql --skip-column-names \
                -h $MYSQL_HOST \
                -u $MYSQL_USER \
                --password=$MYSQL_PASSWORD \
                $database | \
      grep -v "$ignore"
  fi  
} # }}}

function get_views() # {{{
{
  local database=$1

  if is_version_5
  then
    echo "select TABLE_NAME from VIEWS where TABLE_SCHEMA = '$database';" \
        | mysql --skip-column-names \
                -h $MYSQL_HOST \
                -u $MYSQL_USER \
                --password=$MYSQL_PASSWORD \
                information_schema
  fi
} # }}}

function get_functions() # {{{
{
  local database=$1

  if is_version_5
  then
    echo "select ROUTINE_NAME from ROUTINES " \
         " where ROUTINE_SCHEMA = '$database'" \
         "  and  ROUTINE_TYPE   = 'FUNCTION';" \
        | mysql --skip-column-names \
                -h $MYSQL_HOST \
                -u $MYSQL_USER \
                --password=$MYSQL_PASSWORD \
                information_schema
  fi
} # }}}

function get_procedures() # {{{
{
  local database=$1

  if is_version_5
  then
    echo "select ROUTINE_NAME from ROUTINES " \
         " where ROUTINE_SCHEMA = '$database'" \
         "  and  ROUTINE_TYPE   = 'PROCEDURE';" \
        | mysql --skip-column-names \
                -h $MYSQL_HOST \
                -u $MYSQL_USER \
                --password=$MYSQL_PASSWORD \
                information_schema
  fi
} # }}}

function get_version() # {{{
{
  mysql_config --version
} # }}}

function is_version_5() # {{{
{
  local v=`get_version`
  if test "${v:0:1}" = "5"
  then
    return 0
  fi
  return 1
} # }}}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Ist noch genug Platz auf der Platte fuer ein Backup?
DISK_SPACE=`/bin/df /dev/xvda2 | /usr/bin/grep 'xvda2' | /usr/bin/awk '{ print $4/1024/1024 }'`

if test $DISK_SPACE -le 10
then
  echo "Es gibt nicht genuegend Platz auf der Festplatte fuer ein Backup: nur ${DISK_SPACE}G noch frei" | \
       notify_admin "zu wenig Plattenplatz fuer Backup"
  exit 1
fi

# Das Ziel-Verzeichnis vorbereiten.
if test -e $DUMP_DIR_BASE
then
  rm -rf $DUMP_DIR_BASE
fi

/bin/mkdir $DUMP_DIR_BASE

if test $? -ne 0 
then
  echo "Kann das Backup-Verzeichnis ${DUMP_DIR_BASE} nicht anlegen" | \
       notify_admin "Backup-Verzeichnis kann nicht erstellt werden"
fi

/bin/mkdir $DUMP_DIR 

if test $? -ne 0 
then
  echo "Kann das Backup-Verzeichnis ${DUMP_DIR_BASE} nicht anlegen" | \
       notify_admin "Backup-Verzeichnis kann nicht erstellt werden"
fi


# Und jetzt... Fuer jede Database
(
  echo "show databases;" 
) | mysql --skip-column-names \
          -h $MYSQL_HOST \
          -u $MYSQL_USER \
          --password=$MYSQL_PASSWORD | \
    grep -v "^test" | \
while read database
do
  if test "$database" = "information_schema" -o \
          "$database" = "test" -o 
  then
    continue
  fi

  echo "===== $DUMP_DIR/$database ====="
  
  if test "$ENABLE_MYSQLHOTCOPY" = "TRUE" # {{{
  then
    # wenn wir auf 'localhost' sind fueren wir ein 'mysqlhotcopy' durch
    if test "$MYSQL_HOST" = "localhost" -o "$MYSQL_HOST" = "`hostname -f`"
    then
      mkdir -p $DUMP_DIR/hotcopy

      # Index-Dateien werden mit kopiert, damit wir mal ein myisamchk machen koennen
      mysqlhotcopy -u $MYSQL_USER \
                   --password=$MYSQL_PASSWORD \
                   $database \
                   $DUMP_DIR/hotcopy

      tar --create --directory=$DUMP_DIR/hotcopy --file=$DUMP_DIR/hotcopy/$database.tar $database
      gzip $DUMP_DIR/hotcopy/$database.tar
      rm -rf $DUMP_DIR/hotcopy/$database
    fi
  fi # }}}

  if test "$ENABLE_MYSQLDUMP" = "TRUE" -o "$ENABLE_VERSION5_EXTENSIONS" = "TRUE" # {{{
  then
    mkdir -p $DUMP_DIR/$database
  fi # }}}

  if test "$ENABLE_MYSQLDUMP" = "TRUE" # {{{
  then
    # jetzt noch einen normalen Dump

    echo "create database if not exists $database;" \
                                    >$DUMP_DIR/$database/create_database.sql
    dump_create_tables     $database $DUMP_DIR/$database
    dump_table_data        $database $DUMP_DIR/$database
  fi # }}}

  if test "$ENABLE_VERSION5_EXTENSIONS" = "TRUE" # {{{
  then
    if is_version_5
    then
      dump_create_views      $database $DUMP_DIR/$database
      dump_create_functions  $database $DUMP_DIR/$database
      dump_create_procedures $database $DUMP_DIR/$database
    fi
  fi # }}}
done

if test "${ENABLE_ARCHIVING_BACKUP}" = "TRUE"
then
  # Nun legen wir das Backup ins Archiv
  /usr/bin/dsmc i ${DUMP_DIR_BASE} -su=yes

  if test $? -ne 0 
  then
    echo "Es ist ein Fehler beim Ablegen des Backups auf den zentralen Backup-Server aufgetreten" |\
         notify_admin "Allgemeiner Fehler"
  else
    echo "Backup ins Archiv gelegt"
  fi
fi

