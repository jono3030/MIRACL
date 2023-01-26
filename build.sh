#!/bin/bash

# Build MIRACL Docker image with user information from host system
#
# - Checks if Docker and Docker Compose are installed
# - Dynamically adds and removes user information to
#   prevent errors in Singularity container creation
# - Container user is the same as host user to prevent
#   X11 issues with miraclGUI
#
# Current maintainer of script: Jonas Osmann @ github.com/jono3030
# MIRACL (C) Maged Groubran @ maged.goubran@utoronto.ca

# Script version
version="1.1.1-beta"

# Set log variable
write_log=false

# Usage function
function usage()
{

 cat <<usage

 Automatically build MIRACL Docker image with pseudo host user

 Version: $version

 Usage: ./build.sh

 Arguments:

   -h,--help: Prints this help menu

   -l, --log: Writes logfile of build process to build.log

usage

}

# Basic flags function
# Will be expanded in next iteration of MIRACL
while [ ! $# -eq 0 ]
do
  if [ "$*" = "-h" ] || [ "$*" = "--help" ];
  then
    usage
    exit 0
  elif [ "$*" = "-l" ] || [ "$*" = "--log" ];
  then
    write_log=true
  else
    printf "\'$*\' is not a valid argument\n"
    exit 1
  fi
  shift
done 

# Information that needs to be added to Dockerfile
# to create pseudo host user. This is required to
# make X11 work correclty with miraclGUI
USER_TEXT=$(cat <<END
# Setup host user as container user\n\
ARG USER_ID=\$USER_ID\n\
ARG GROUP_ID=\$GROUP_ID\n\
ARG USER=\$USER\n\n\
RUN addgroup --gid \$GROUP_ID \$USER\n\
RUN adduser --disabled-password --gecos '' --uid \$USER_ID --gid \$GROUP_ID \$USER\n\n\
# Change owner of /code directory\n\
RUN chown -R \$USER:\$USER /code\n\
# Change to \$USER\n\
USER \$USER\n\
WORKDIR /home/\$USER
END
)

function rm_USER_TEXT () {
  sed -i '/STARTUNCOMMENT/,/STOPUNCOMMENT/{//!d}' Dockerfile
}

# Check if $USER_TEXT strings are already present and delete if true
if [ "$(sed -n '/#STARTUNCOMMENT#/{n;p;}' Dockerfile)" != "#STOPUNCOMMENT#" ]; then
       	rm_USER_TEXT
fi

# Check if Docker is installed
if [ -x "$(command -v docker)" ]; then
	    printf "\nDocker installation found. Building image.\n"
      # Adding host user requirements to Dockerfile
      sed -i "/#STARTUNCOMMENT#/a $USER_TEXT" Dockerfile
	    # Change user in docker-compose.yml to host user
	    export HOST_USER=$(whoami)
	    sed -i "s/\(\/home\/\).*\(\/.Xauthority:\/home\/\).*\(\/.Xauthority\)/\1$HOST_USER\2$HOST_USER\3/g" docker-compose.yml
	    # Build MIRACL image from Dockerfile
	    # Pass user name, UID and GID to Dockerfile
      function docker_build () {
	      docker build \
	      --build-arg USER_ID=$(id -u) \
	      --build-arg GROUP_ID=$(id -g) \
	      --build-arg USER=$HOST_USER \
	      -t mgoubran/miracl .
      }

      # Check for log flag
      if [ $write_log = true ];
      then
        docker_build | tee build.log
      else
        docker_build
      fi

      # Check if build process exited without errors
      build_status_code=$?
      if [ $build_status_code -eq 0 ]; then
        printf "\nBuild was successful! Checking Docker Compose installation.\n"
        # Remove $USER_TEXT from Dockerfile
        rm_USER_TEXT

        # Test if docker-compose is installed
        # Should come by default with Docker-Desktop
        if [ -x "$(command -v docker-compose)" ]; then
          printf "Docker Compose installation found <<$(docker-compose --version)>>). Run 'docker-compose up -d' to start the MIRACL container in background.\n"
        elif dcex=$(docker compose --version); then
          printf "Docker Compose installation found (<<%s>>). Run 'docker compose up -d' or use Docker Desktop (if installed) to start the MIRACL container in background.\n" "$dcex"
        else
          printf "Docker Compose installation not found. Please install Docker Compose plugin or standalone version to run the MIRACL container. Instructions on how to install Docker Compose can be found here: https://docs.docker.com/compose/install/\n"
        fi
      else
        # Return error code if build was not successful
        printf "\nBuild not successful! An error occured with exit code: $build_status_code\n"
        # Remove $USER_TEXT from Dockerfile
        rm_USER_TEXT
      fi

else
    di_status_code=$?
    printf "\nDocker installation not found. Please install Docker first.\n"
    printf "Exiting with status code $di_status_code\n"
    exit di_status_code
fi