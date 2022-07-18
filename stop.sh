#!/bin/bash
VARIABLE_SUM=$#
CONTAINER_NAMES=$@
CONTAINER_VALID_LIST="nginx lambdas content-server archipelago nats nats-exporter explorer-bff"

printMessage () {
    Type=$1
    case ${Type} in
      ok) echo -e "[\e[92m OK \e[39m]" ;;
      failed) echo -e "[\e[91m FAILED \e[39m]" ;;
      *) echo "";;
    esac
}

if test ${VARIABLE_SUM} -eq 0; then
  echo "## Stopping catalyst node..."
  docker-compose stop
  if test $? -ne 0; then
    echo -n "Failed to stop catalyst node "
    printMessage failed
    exit 1
  fi
  echo -n "## node stopped Ok... "
else
  for i in `echo ${CONTAINER_NAMES}`; do
    echo -ne "## Trying to stop ${i}: \t"

    #Check if the service exists
    echo ${CONTAINER_VALID_LIST} | grep --quiet ${i}
    if  test $? -eq 0; then
      docker-compose stop ${i}
      if  test $? -eq 0; then
          echo "`printMessage ok`. Container ${i} was stopped"
        else
          echo "`printMessage failed`. Unable to stop ${i}"
        fi
    else
      echo "`printMessage failed`. The service ${i} does not exists"
    fi
  done
fi
