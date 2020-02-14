#!/bin/bash

printMessage () {
    Type=$1
    case ${Type} in
      ok) echo -e "[\e[92m OK \e[39m]" ;;
      failed) echo -e "[\e[91m FAILED \e[39m]" ;;
      *) echo "";;
    esac
}

echo "## Stopping catalyst node..."
docker-compose stop

##C hecking if everything went Ok
###
if test $? -ne 0; then
  echo -n "Failed to stop catalyst node "
  printMessage failed
  exit 1
fi
echo -n "## node stopped Ok... "
printMessage ok