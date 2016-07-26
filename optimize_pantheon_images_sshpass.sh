#!/bin/bash

# This script relies on jpegtran, a tool included with libjpeg.
# libjpeg comes bundled with ImageMagick on most nix platforms:
# 
# 	Mac: 
# 	brew install imagemagick
# 	
# 	Ubuntu/Debian: 
# 	sudo apt-get install gcc
# 	sudo apt-get install imagemagick
# 	
# 	CentOS/Fedora/RHEL: 
# 	yum install gcc php-devel php-pear
# 	yum install ImageMagick ImageMagick-devel
# 	
# 	Windows:
# 	.... well.... sorry, i'm not sure about this one. 


function optimize_pantheon_images() {

        RETRY_DELAY=120
        RSYNC_DL_COUNT=0
        RSYNC_RETRIES=10

	# checks for the presence of jpegtran, which we use for image optimization
	command -v jpegtran >/dev/null 2>&1 || { echo >&2 "I require jpegtran but it's not installed. Aborting."; exit 1; }

	# checks for the presence of sshpass, which we use to pass credentials to rsync
	command -v sshpass >/dev/null 2>&1 || { echo >&2 "I require sshpass but it's not installed. Aborting."; exit 1; }

	# checks to make sure the desired working directory exists
	read -p "Local Files Root Directory (./files): " DIR
	if [ ! -d $DIR ]; then
		echo "$DIR is not a directory. Aborting"
		exit 1
	fi

	# ask for the env
	read -p "Pantheon Environment (dev|test|live): " PANTHEON_ENV
	export ENV=$PANTHEON_ENV

	# ask for the site id
	read -p "Pantheon Site ID (XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX): " PANTHEON_UUID
	export SITE=$PANTHEON_UUID

	# ask for the pantheon password
	read -sp "Pantheon Password: " PASSWORD

	# remember where we started off so we can return later
	# cd into working directoy
	echo "Changing to $DIR"
	CUR_DIR=$(pwd)
	cd $DIR

	# download files
	echo "Downloading Files"
	while [  $RSYNC_DL_COUNT -lt $RSYNC_RETRIES ]; do
		sshpass -p "$PASSWORD" rsync -am --include='*.jpg' --include='*.jpeg' --include='*/' --exclude='*' --partial -rlvz --size-only --ipv4 --progress -e "ssh -p 2222 -o StrictHostKeyChecking=no" $ENV.$SITE@appserver.$ENV.$SITE.drush.in:files/* ./files/
		if [ "$?" = "0" ] ; then
			echo "Download completed"
			break
		else
			echo "Download failure. Backing off and retrying in $RETRY_DELAY seconds ($RSYNC_DL_COUNT)"
			sleep $RETRY_DELAY
		fi
		let RSYNC_DL_COUNT=RSYNC_DL_COUNT+1 
	done # rsync retry loop

	# optimize jpgs
	FILES=$(find . -iname '*.jpg' -o -iname '*.jpeg')
	for F in $FILES; do
		echo "Optimizing: $F"
		jpegtran -copy none -progressive -outfile "$F" "$F"
	done

	# upload files
	echo "Uploading Files"
	sshpass -p "$PASSWORD" rsync -am --include='*.jpg' --include='*.jpeg' --include='*/' --exclude='*' --partial -rlvz --size-only --ipv4 --progress -e "ssh -p 2222 -o StrictHostKeyChecking=no" . --temp-dir=../tmp/ $ENV.$SITE@appserver.$ENV.$SITE.drush.in:files/.
	if [ "$?" = "0" ] ; then
		echo "Upload completed"
	else
		echo "Upload failure. Backing off and retrying..."
		sleep 180
	fi

	echo "Done"

	# return back to where we came from
	cd $CUR_DIR
}

optimize_pantheon_images
