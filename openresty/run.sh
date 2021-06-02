 #!/usr/bin/env bash

DOCKER_IMAGE_NAME="decentraland/openresty"

docker build -t $DOCKER_IMAGE_NAME .

docker run -d -p 8080:8080 $DOCKER_IMAGE_NAME

DOCKER_ID=$(docker ps | grep $DOCKER_IMAGE_NAME | awk '{ print $1 }')

echo "Running docker image: $DOCKER_ID"

# docker exec -it ${DOCKER_ID} /bin/sh
