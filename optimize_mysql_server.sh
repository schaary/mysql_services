#!/bin/bash

# Dieses Skript fuehrt fuer alle Datenbanken eines Datenbank-Servers einen
# Check durch. Wenn dabei keine Fehler festgestellt werden konnten, werden alle
# Datenbanken anschliessend optimiert.
#
# ms, 08.10.2009

# Sollen die Datenbanken nach dem fehlerfreien check
# auch gleich optimiert werden?
ENABLE_OPTIMIZE="TRUE"

# Soll das Ergebnis sofort ins Archiv gelegt werden?
ENABLE_ARCHIVING_BACKUP="TRUE"

# Die Fehlermeldungen werden an folgende Adressen gemeldet
mailadressen=('michael.schaarschmidt@urz.uni-halle.de' \
              'dirk.pollmaecher@urz.uni-halle.de' \
              'kristina.haase@urz.uni-halle.de')

# Das Verzeichnis fuer die Logdateien wird erstellt
# Wenn sich das Verzeichnis nicht erstellen laesst, wird das Skript mit einer
# Fehlermeldung an die Admins abgebrochen
date=`date +%Y%m%d`
LOGDIR_BASE="/archiv/check/"
LOGDIR="${LOGDIR_BASE}/${date}/"

if test -e ${LOGDIR_BASE}
then
  /bin/rm -rf ${LOGDIR_BASE}
fi

/bin/mkdir ${LOGDIR_BASE}

if test $? -ne 0
then
  echo "Kann das Log-Verzeichnis fuer den Datenbank-Check nicht erstellen" |\
       notify_admin "Allgemeines Problem"
  exit 1
fi 

/bin/mkdir ${LOGDIR}

if test $? -ne 0
then
  echo "Kann das Log-Verzeichnis fuer den Datenbank-Check nicht erstellen" |\
       notify_admin "Allgemeines Problem"
  exit 1
fi 

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
  local mail_body=$(cat) # liest alles von stdin

  for mailadresse in ${mailadressen[*]}
  do
    echo $mail_body | mail -s "FEHLER bei mysqlcheck auf ${HOSTNAME} - $1" $mailadresse
  done
}  # }}}

function get_tables() # {{{
{
  local database=$1

  (
    echo "SELECT TABLE_NAME"
    echo "  FROM information_schema.TABLES"
    echo " WHERE TABLE_SCHEMA = '$database'" 
    echo "   AND ENGINE='MYISAM'" 
    echo " ORDER BY TABLE_NAME"
    echo ";" 
  ) | \
    mysql --skip-column-names \
              -h $MYSQL_HOST \
              -u $MYSQL_USER \
              --password=$MYSQL_PASSWORD \
              information_schema
} # }}}

function check_database() # {{{
{
  local database=$1
  local LOGFILE=$2

  for table in `get_tables $database`
  do
    echo "checke die ${database}.${table}"
    mysqlcheck --silent \
               --medium-check \
               --user=$MYSQL_USER \
               --host=$MYSQL_HOST \
               --password=$MYSQL_PASSWORD \
               $database $table >> $LOGFILE
  done
} # }}}

function optimize_database() # {{{
{
  local database=$1
  local OPTIMIZEFILE=$2

  for table in `get_tables $database`
  do
    echo "optimiere die ${database}.${table}"
    mysqlcheck --optimize \
               --user=$MYSQL_USER \
               --host=$MYSQL_HOST \
               --password=$MYSQL_PASSWORD \
               $database $table >> $OPTIMIZEFILE
  done
} # }}}

# Und jetzt... fuer jede Database
(
  echo "show databases;" 
) | mysql --skip-column-names \
          -h $MYSQL_HOST \
          -u $MYSQL_USER \
          --password="${MYSQL_PASSWORD}" |\
while read database
do
  if test "$database" = "information_schema" -o \
          "$database" = "test" -o \
          "$database" = "studip_20090925"
  then
    continue
  fi
 
  # Hier werden die Namen der Logdateien festgelegt
  # Um moegliche Kollisionen zu vermeiden, haengen wir 
  # die aktuelle Prozess-ID ($$) an den Dateinamen
  LOGFILE="${LOGDIR}/${database}_check_$$.log"
  OPTIMIZEFILE="${LOGDIR}/${database}_optimize_$$.log"

  # checken die Datenbank
  check_database $database $LOGFILE

  # hier zahlen wir die Verwundeten
  lines=`cat $LOGFILE | wc -l`

  if test $lines -ne 0 
  then
    cat $LOGFILE | notify_admin $database
  else
    if test "$ENABLE_OPTIMIZE" = "TRUE"
    then
      # optimieren die Datenbank
      optimize_database $database $OPTIMIZEFILE
    fi
  fi
done

if test "${ENABLE_ARCHIVING_BACKUP}" = "TRUE"
then
  # Nun legen wir das Backup ins Archiv
  /usr/bin/dsmc i ${LOGDIR_BASE} -su=yes

  if test $? -ne 0 
  then
    echo "Es ist ein Fehler beim Ablegen des Check-Verzeichnisses auf den zentralen Backup-Server aufgetreten" |\
         notify_admin "Allgemeiner Fehler"
  else
    echo "Check-Verzeichnis ins Archiv gelegt"
  fi
fi

