#!/bin/bash
echo '_________________________________'
echo "######## STEP 0 ################"
DOCKER_CHECK=$(docker run --rm hello-world 2>&1)

# Check if Docker is running fine

if [[ $DOCKER_CHECK =~ "Hello from Docker!" ]]; then
  echo "Seems Docker is fine... Let's proceed"
  docker --version
  docker compose version
else 
  echo "ERROR: Something wrong with docker"
  docker version
  exit 1
fi

echo '__________docker-ready___________'
# (Rancher Desktop / rdctl part removed: not needed on Ubuntu with a native Docker Engine)
until docker info >/dev/null 2>&1; do
  echo "Docker daemon not running yet... pause 10 seconds"
  sleep 10
done
docker container prune -f
echo "Docker is ready! 🐳"

#Check and remove existing containers and volumes
echo '_________________________________'
echo "######## STEP 1 ################"

echo "Checking for image updates"
docker pull web2wol/wp:1.3
docker pull web2wol/wp-db:latest

echo ''
echo "Need to check Containers and Volumes before we start"
# Check if the containers "wp" and "wp-db" exist
if docker volume ls | grep -q 'wp\|wp-db'; then
    # Remove the volumes "wp" and "db" if they exist
    docker rm -f wp wp-db
    echo "Containers 'wp' and 'wp-db' have been removed."
else
    echo "Containers 'wp' and 'wp-db' do not exist."
fi

# Check if the volumes "wp" and "db" exist
if docker volume ls | grep -q 'wp\|db'; then
    # Remove the volumes "wp" and "db" if they exist
    docker volume rm wp db
    docker network rm pte-network 2>/dev/null || true
    echo "Volumes 'wp' and 'db' have been removed."
else
    echo "Volumes 'wp' and 'db' do not exist."
fi
echo '_________________________________'
echo "######## STEP 2 ################"

# Define the Docker Compose content
COMPOSE_CONTENT=$(cat <<EOF
name: pte

services:
  wordpress:
    platform: linux/amd64
    image: web2wol/wp:1.3
    restart: always
    container_name: wp
    ports:
      - 80:80
    environment:
      WORDPRESS_DB_HOST: db
      WORDPRESS_DB_USER: exampleuser
      WORDPRESS_DB_PASSWORD: examplepass
      WORDPRESS_DB_NAME: exampledb
    volumes:
      - wp:/var/www/html
    # deploy:
    #   resources:
    #     limits:
    #       cpus: '2.0'
    #     reservations:
    #       cpus: '2.0'

  # wp_db_vol:
  #   image: web2wol/wp_db_vol:latest
  #   volumes:
  #     - db:/var/lib/mysql


  db:
    platform: linux/amd64
    image: web2wol/wp-db:latest
    restart: always
    container_name: wp-db
    environment:
      MYSQL_DATABASE: exampledb
      MYSQL_USER: exampleuser
      MYSQL_PASSWORD: examplepass
      MYSQL_RANDOM_ROOT_PASSWORD: '1'
    volumes:
      # - wp_db_vol
      # --mount source=wp_db_vol,target=/var/lib/mysql
      - db:/var/lib/mysql
    command: --max-connections=50
    deploy:
      resources:
        limits:
          cpus: '1.0'
        reservations:
          cpus: '1.0'

volumes:
  wp:
    name: wp
  db:
    name: db

networks:
  default:
    name: pte-network
EOF
)

# Define the file name for the Docker Compose file
COMPOSE_FILE="docker-compose.yaml"

# Write the Docker Compose content to the file
echo "$COMPOSE_CONTENT" > "$COMPOSE_FILE"
echo "compose created successfully"


echo '_________________________________'
echo "######## STEP 3 ################"
# Run the Docker Compose file
docker compose up -d
docker ps -a

echo "Docker Compose file created and the service is now running."

#Backup-----
#docker run --rm -v wp:/volume -v ./:/backup busybox tar -czf /backup/wp_backup.tar -C /volume .
#docker run --rm -v db:/volume -v ./:/backup busybox tar -czf /backup/wp_db_backup.tar -C /volume . 

echo '_________________________________'
echo "######## STEP 4 ################"

#Get app and db backups
echo "Extracting backups..."
docker cp wp:/tmp/wp_backup.tar ./
docker cp wp:/tmp/wp_db_backup.tar ./
echo "Extracting backups. Done!"

#Restore backups to its volumes
echo "Restoring backups..."

docker run --rm --platform linux/amd64 -v db:/volume -v "$(pwd)"/:/backup busybox tar -xzf /backup/wp_db_backup.tar -C /volume
docker run --rm --platform linux/amd64 -v wp:/volume -v "$(pwd)"/:/backup busybox tar -xzf /backup/wp_backup.tar -C /volume
echo "Restore backups. Done!"


echo '_________________________________'
echo "######## STEP 5 ################"
#Restart app
echo "Restarting App and DB"
docker restart wp wp-db

#Clean up
echo "Clean up"
rm -f wp_backup.tar wp_db_backup.tar docker-compose.yaml
echo "Clean up: Done!"

echo '_________________________________'
echo "######## STEP 6 ################"
echo "Let's check the App"

# Wait until the app answers (up to ~2 minutes)
response_code=000
for i in $(seq 1 24); do
    response_code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/)
    [ "$response_code" == "200" ] && break
    echo "App not ready yet (HTTP $response_code)... retry $i/24"
    sleep 5
done

if [ "$response_code" == "200" ]; then
    echo "HTTP response code is $response_code"
    echo "Now you are all set! :) and can strive to the performance excellence."

else
    echo "=========== DEBUG SECTION ==========="
    echo "HTTP response code is $response_code, not 200 OK."
    echo "ALARM ->->-> Something WRONG! :( :( :( :( :( :( :( :( :( :("
    echo "---> Trying to check DB State and connection"

    docker exec -t wp apt-get update
    docker exec -t wp apt-get install -y default-mysql-client  # Install MySQL client
    docker exec -t wp mysql -h db -u exampleuser -pexamplepass exampledb -e "SELECT * FROM wp_users;"

    echo "---> Trying to check Containers and Volumes wp=119.4MB, wp-db=232.2MB"
    docker system df -v
    echo "=========== DEBUG SECTION ==========="


    exit 1
fi


