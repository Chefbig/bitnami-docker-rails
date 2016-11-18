#!/bin/bash
set -e

INIT_SEM=/tmp/initialized.sem

fresh_container() {
  [ ! -f $INIT_SEM ]
}

app_present() {
  [ -f /app/config.ru ]
}

gems_up_to_date() {
  bundle check 1> /dev/null
}

wait_for_db() {
  mariadb_address=$(getent hosts mariadb | awk '{ print $1 }')
  counter=0
  log "Connecting to mariadb at $mariadb_address"
  while ! nc -z mariadb 3306; do
    counter=$((counter+1))
    if [ $counter == 30 ]; then
      log "Error: Couldn't connect to mariadb."
      exit 1
    fi
    log "Trying to connect to mariadb at $mariadb_address. Attempt $counter."
    sleep 5
  done
}

setup_db() {
  log "Configuring the database"
  bundle exec rails db:create
}

migrate_db() {
  log "Applying database migrations (db:migrate)"
  bundle exec rails db:migrate
}

log () {
  echo -e "\033[0;33m$(date "+%H:%M:%S")\033[0;37m ==> $1."
}

if [ "$1" == "bundle" -a "$2" == "exec" ]; then
  if ! app_present; then
    log "Creating rails application"
    rails new . --skip-bundle --database mysql
    # Add rubyracer
    sed -i "s/# gem 'therubyracer'/gem 'therubyracer'/" Gemfile
  fi

  if ! gems_up_to_date; then
    log "Installing/Updating Rails dependencies (gems)"
    bundle install
    log "Gems updated"
  fi

  wait_for_db

  if ! fresh_container; then
    echo "#########################################################################"
    echo "                                                                       "
    echo " App initialization skipped:"
    echo " Delete the file $INIT_SEM and restart the container to reinitialize"
    echo " You can alternatively run specific commands using docker-compose exec"
    echo " e.g docker-compose exec rails bundle exec rails db:migrate"
    echo "                                                                       "
    echo "#########################################################################"
  else
    setup_db
    log "Initialization finished"
    touch $INIT_SEM
  fi

  migrate_db
fi

exec /entrypoint.sh "$@"
