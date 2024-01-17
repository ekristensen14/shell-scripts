#!/bin/sh

# Define variables
userName=$(ls -l /dev/console | awk '{ print $3 }') 
teamsimage=""
ziplocation="/tmp/"
imagefile="backgrounds.zip"

##
## Attempt to download the image file. No point checking if it already exists since we want to overwrite it anyway
##

echo "$(date) | Downloading background images from [$teamsimage] to [$ziplocation/$imagefile]"
curl -L -o $ziplocation/$imagefile $teamsimage
if [ "$?" = "0" ]; then
   echo "$(date) | Wallpaper [$teamsimage] downloaded to [$ziplocation/$imagefile]"
else
   echo "$(date) | Failed to download wallpaper image from [$teamsimage]"
   exit 1
fi

for i in $userName
do
    NEWTEAMS="/Users/$i/Library/Containers/com.microsoft.teams2/Data/Library/Application Support/Microsoft/MSTeams/Backgrounds/Uploads/"
    OLDTEAMS="/Users/$i/Library/Application Support/Microsoft/Teams/Backgrounds/Uploads/"
    if [ -d "$OLDTEAMS" ]
    then
        echo "$(date) | Classic Teams dir [$OLDTEAMS] already exists"
        echo "$(date) | Cleaning up old images"
        rm -rf "$OLDTEAMS"
        unzip -o $ziplocation/$imagefile -d "$OLDTEAMS"
    else
        echo "$(date) | Classic Teams not installed"
    fi

    if [ -d "$NEWTEAMS" ]
    then
        echo "$(date) | New Teams dir [$NEWTEAMS] already exists"
        echo "$(date) | Cleaning up old images"
        rm -rf "$NEWTEAMS"
        unzip -o $ziplocation/$imagefile -d "$NEWTEAMS"
    else
        echo "$(date) | New Teams not installed"
    fi

    pkill -U $i cfprefsd
done
