#!/bin/bash
Ver="2401.23"
#set -x

############################################################################################
##
## Script to set the computer hostname
##
############################################################################################

# User Defined variables
clientID=""
secretValue=""
tenantID=""

# Standard Variables
userName=$(ls -l /dev/console | awk '{ print $3 }') 
headers=(-H "Content-Type: application/x-www-form-urlencoded")
logDir="/Library/logs/Microsoft/IntuneScripts/RenameHost"

if [ -d $logoDir ]; then
    ## Already created
    echo "$(date) | logo directory already exists - $logoDir"
else
    ## Creating Metadirectory
    echo "$(date) | creating logo directory - $logoDir"
    mkdir -p $logoDir
fi

# Generated Variables
url="https://login.microsoftonline.com/$tenantID/oauth2/v2.0/token"
#data="client_id=$clientID&scope=https%3A%2F%2Fgraph.microsoft.com%2F.default&client_secret=$secretValue&grant_type=client_credentials"
data="client_id=$clientID&scope=https://graph.microsoft.com/.default&client_secret=$secretValue&grant_type=client_credentials"

## Check if the log directory has been created
if [ -d $logDir ]; then
	## Already created
	echo "$(date) | log directory already exists - $logDir"
else
	## Creating Metadirectory
	echo "$(date) | creating log directory - $logDir"
	mkdir -p $logDir
fi

# function to delay until the user has finished setup assistant.
waitForDesktop () {
  until ps aux | grep /System/Library/CoreServices/Dock.app/Contents/MacOS/Dock | grep -v grep &>/dev/null; do
    delay=$(( $RANDOM % 50 + 10 ))
    echo "$(date) |  + Dock not running, waiting [$delay] seconds"
    sleep $delay
  done
  echo "$(date) | Dock is here, lets carry on"
}

# start logging
exec &> >(tee -a "$log")

# Begin Script Body
echo ""
echo "##############################################################"
echo "# $(date) | Starting run MacOS Renamer ([$Ver])"
echo "############################################################"
echo ""

# We don't want to interrupt setup assistant
waitForDesktop

# Attempt to read UPN from OfficeActivationEmailAddress
officePlistPath="/Library/Managed Preferences/com.microsoft.office.plist"

# Set Max Retries
max_retries=10
retries=0

until [ -e "$officePlistPath" ]; do
    # Check if the current time has exceeded the end time
    echo "$(date) | Looking for Office Plist File [$officePlistPath]"
    if [ "$retries" -ge "$max_retries" ]; then
        echo "$(date) | Office plist file not found [$officePlistPath]"
        exit 1
    fi

    # If the file is not found, sleep for the specified interval
    ((retries++)) 
    sleep 30
done

echo "$(date) | Office plist file found [$officePlistPath]"


echo "$(date) | Trying to determine UPN from OfficeActivationEmailAddress"
UPN=$(defaults read /Library/Managed\ Preferences/com.microsoft.office.plist OfficeActivationEmailAddress)
if [ $? == 0 ]; then
    echo "$(date) |  + UPN found as [$UPN]"
else
    echo "$(date) |  + UPN not found, exiting (did you set Office Activation e-Mail is Settings Picker?)"
    exit 1
fi

# Attempt to get a token from Entra
echo "$(date) | Getting the Token"
token=$(curl -s -X POST "${headers[@]}" -d "$data" "$url" | sed -E 's/.*"access_token":"([^"]+)".*/\1/')

#Use the Token to download the get the firstname and lastname
select='$select=displayName'
fullnameURL="https://graph.microsoft.com/beta/users/$UPN/?$select"
headers2="Authorization: Bearer $token"
echo "$(date) | getting the display name"

# Get displayname and select only first and lastname
fullname=$(curl -s --location --request GET "$fullnameURL" --header "${headers2[@]}" | sed -E 's/.*"displayName":"([^"]+)".*/\1/' | awk '{print $1, $NF}')

# Generate the new device name, limiting at 14 characters (to make room for a number). Starting with "p44-" and adding the first initial and last name all in lowercase
baseDeviceName="p44-$(echo $fullname | awk '{print $1}' | cut -c1)$(echo $fullname | awk '{print $2}' | cut -c1-13)"
# Set newDeviceName to lowercase
baseDeviceName=$(echo $baseDeviceName | tr '[:upper:]' '[:lower:]')
newDeviceName=$baseDeviceName

# Get the current device name
currentDeviceName=$(scutil --get ComputerName)

# Check if the device name already begins with p44-
if [[ $currentDeviceName == p44-* ]]; then
    echo "$(date) | Device name already begins with p44-"
    echo "$(date) |  + Current Device Name: $currentDeviceName"
    echo "$(date) |  + Exiting"
    exit 0
else
    echo "$(date) | Device name does not begin with p44-"
    echo "$(date) |  + Current Device Name: $currentDeviceName"
    # Check if the new device name is already in use in Intune
    echo "$(date) | Checking if the new device name is already in use in Intune"
    deviceNameInUse=$(curl -s --location --request GET --header "${headers2[@]}" "https://graph.microsoft.com/beta/deviceManagement/managedDevices/?\$filter=devicename%20eq%20'$newDeviceName'" | grep -io "$newDeviceName" | wc -l)
    # If the device name is already in use, add a number starting from 2 to the end of the device name
    if [[ $deviceNameInUse -gt 0 ]]; then
        echo "$(date) | Device name is already in use in Intune"
        echo "$(date) |  + Adding a number to the end of the device name"
        # Set the number to 2
        number=2
        # Loop until the device name is not in use
        while [[ $deviceNameInUse -gt 0 ]]; do
            # Add the number to the end of the device name
            newDeviceName="$baseDeviceName$number"
            # Check if the new device name is already in use in Intune
            deviceNameInUse=$(curl -s --location --request GET --header "${headers2[@]}" "https://graph.microsoft.com/beta/deviceManagement/managedDevices/?\$filter=devicename%20eq%20'$newDeviceName'" | grep -io "$newDeviceName" | wc -l)
            # Increment the number
            ((number++))
        done
        echo "$(date) |  + New Device Name: $newDeviceName"
    else 
        # If the device name is not in use, set the new device name to the base device name
        newDeviceName=$baseDeviceName
        echo "$(date) |  + New Device Name: $newDeviceName"    
    fi

    # Set the new device name
    scutil --set ComputerName $newDeviceName
    scutil --set LocalHostName $newDeviceName
    scutil --set HostName $newDeviceName
    sudo echo "$(date) |  + Device name changed"

    

    # Notify user that the device name has been changed and ask them to restart
    title="Device Name Changed"
    message="Your device name has been changed to comply with company IT standards."
    message4="Please restart your device to apply the change."
    message2="Thank you for your cooperation."
    message3="project44 IT Team"
    combined="$message\n\n$message4\n\n$message2\n\n$message3"

    # Get the currently logged in user's name
    userName=$(stat -f%Su /dev/console)

    # Get the user's ID
    uid=$(id -u $userName)

    # Get the user's login session ID
    loginSessionId=$(sudo launchctl asuser $uid launchctl list | grep -v PID | awk '/com.apple.*/ { print $3; exit }')

    # Create a .plist file for the task
    mkdir -p /Users/$userName/Library/LaunchAgents

    # Create a shell script that waits for Microsoft Defender to start, performs the scan, and then deletes the .plist file
    echo '#!/bin/sh
# Wait for Dock to start
until ps aux | grep /System/Library/CoreServices/Dock.app/Contents/MacOS/Dock | grep -v grep &>/dev/null; do
    delay=$(( $RANDOM % 50 + 10 ))
    echo "$(date) |  + Dock not running, waiting [$delay] seconds"
    sleep $delay
done

echo "$(date) | Dock is here, lets carry on"

# Wait for Microsoft Defender to start
while ! pgrep -x "wdavdaemon" > /dev/null;
do
    delay=$(( $RANDOM % 50 + 10 ))
    echo "$(date) |  + Defender not running, waiting [$delay] seconds"
    sleep $delay
done

mdatp scan quick

launchctl unload /Users/'$userName'/Library/LaunchAgents/com.project44.mdatpscan.plist' > /Users/$userName/Library/LaunchAgents/mdatpscan.sh

    # Make the shell script executable
    chmod a+x /Users/$userName/Library/LaunchAgents/mdatpscan.sh
    

    echo '<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.project44.mdatpscan</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Users/'$userName'/Library/LaunchAgents/mdatpscan.sh</string>
    </array>
</dict>
</plist>' > /Users/$userName/Library/LaunchAgents/com.project44.mdatpscan.plist

    # Load the task into launchd
    chown $userName /Users/$userName/Library/LaunchAgents/mdatpscan.sh /Users/$userName/Library/LaunchAgents/com.project44.mdatpscan.plist
    sudo launchctl asuser $uid launchctl bootstrap gui/$uid /Users/$userName/Library/LaunchAgents/com.project44.mdatpscan.plist

    display_dialog() {
        # Run the osascript command in the user's context
        userChoice=$(sudo launchctl asuser $uid sudo -u $userName osascript -e 'tell app "System Events" to display dialog "'"$combined"'" with title "'"$title"'" buttons {"Restart Now", "Defer for 1 Hour"} default button 2 giving up after 3600')
    }

    handle_user_choice() {
        if [[ $userChoice == *"Restart Now"* ]]; then
            # Restart the device
            echo "$(date) | User chose to restart now"
            sudo shutdown -r now
        elif [[ $userChoice == *"Defer for 1 Hour"* ]]; then
            # User chose "Defer for 1 Hour"
            # Schedule the script to display the dialog again in 1 hour
            (sleep 3600 && run_dialog) &
        fi
    }

    run_dialog() {
        display_dialog
        handle_user_choice
    }

    # Call the function
    run_dialog

fi
