#!/bin/bash

################################################################################################################################
#####                                                                                                                          #
##### Calum Hunter                                                                                                             #
#####                                                                                                                          #
##### Version 0.1   24-09-2014                                                                                                 #
#####                                                                                                                          #
##### Project:      DET NSW - NetBoot Environment Authorization via AD                                                         #
#####                                                                                                                          #
##### Objective:    This script will run at boot on the Netboot Environment image.                                             # 
#####               It will require a user to enter in their AD credentials which will be checked against AD via ldapsearch.   #
#####               If the user provides correct login details and they are in the correct security groups they will be        #
#####               forwarded on to the next stage ie. DeployStudio.                                                           #
#####                                                                                                                          #
################################################################################################################################

# Location of our log file
logfile=/tmp/strapper_log.log

# Redirect all stdout to our log file
exec > $logfile 

# Dev or prod? If we are Dev mode then instead of trying to open deploy studio we simply echo the command that we opening DS - we dont actually open DS
# Also if we are in Dev mode we dont want to actually shut the machine down so we simply echo out the command that are are shutting down and then exit 0
runmode="Dev"
#runmode="prod"

# hard coded DET variables
domain="detnsw.win"         # Our AD domain name
sbase="dc=detnsw,dc=win"    # Our default search base when searching for user accounts etc
sitebase="CN=Sites,CN=Configuration,DC=detnsw,DC=win"   # Our search base when looking for Site information only
ADImagingGroup="DMIG_ET4L_SOE" # The name of the AD Group a user must be a member of in order to image a machine

# Network variables - Get the IP address and the subnet in Hex format
ipaddr=`ifconfig en0 | awk '/inet[ ]/{print $2}'`
netmaskhex=`ifconfig en0 | grep netmask | cut -d' ' -f4`

## CocoaDialog paths
CDRes=`dirname $0` # Current path that this script is running from
#CD_APP="/Applications/CocoaDialog.app" # Use this location for dev testing
CD_APP="CocoaDialog.app" # Location of the App - use this location when bundling with Platypus
CD="$CD_APP/Contents/MacOS/CocoaDialog" # Location of the binary


## Setup the environment for a pashua run function
pashua_run() {
	# Write config file
	pashua_configfile=`/usr/bin/mktemp /tmp/pashua_XXXXXXXXX`
	echo "$1" > $pashua_configfile

	# Find Pashua binary. We do search both . and dirname "$0"
	# , as in a doubleclickable application, cwd is /
	# BTW, all these quotes below are necessary to handle paths
	# containing spaces.
	bundlepath="Pashua.app/Contents/MacOS/Pashua"
	if [ "$3" = "" ]
	then
		mypath=`dirname "$0"`
		for searchpath in "$mypath/Pashua" "$mypath/$bundlepath" "./$bundlepath" \
						  "/Applications/$bundlepath" "$HOME/Applications/$bundlepath"
		do
			if [ -f "$searchpath" -a -x "$searchpath" ]
			then
				pashuapath=$searchpath
				break
			fi
		done
	else
		# Directory given as argument
		pashuapath="$3/$bundlepath"
	fi

	if [ ! "$pashuapath" ]
	then
		echo "Error: Pashua could not be found"
		exit 1
	fi

	# Manage encoding
	if [ "$2" = "" ]
	then
		encoding=""
	else
		encoding="-e $2"
	fi

	# Get result
	result=$("$pashuapath" $encoding $pashua_configfile | perl -pe 's/ /;;;/g;')

	# Remove config file
	rm $pashua_configfile

	# Parse result
	for line in $result
	do
		key=$(echo $line | sed 's/^\([^=]*\)=.*$/\1/')
		value=$(echo $line | sed 's/^[^=]*=\(.*\)$/\1/' | sed 's/;;;/ /g')
		varname=$key
		varvalue="$value"
		eval $varname='$varvalue'
	done

} # pashua_run()


## Create the initial login window configuration box.
loginconf="
# Set transparency: 0 is transparent, 1 is opaque
*.transparency=0.95

# Set window title
*.title = DET NSW Mac OS X Deployment Tool

# Introductory text
tb.type = text
tb.default = Welcome to the DET Mac OS X Deployment Tool.[return]To continue you must be a member of:[return][return]Imaging Group[return][return]Please enter your AD credentials below.[return]Note: You must use your AD Shortname and NOT your UPN.[return]Depending on your network connection this may take a moment.
tb.height = 176
tb.width = 350
tb.x = 20
tb.y = 130

# Username Input
uname.type = textfield
uname.label = Username
uname.default = JSmith24
uname.width = 210
uname.x = 20
uname.y = 60

# Password Input
pword.type = password
pword.label = Password
pword.default = Secret
pword.width = 210
pword.x = 20
pword.y = 0

# Next button
nextbutton1.type = defaultbutton
nextbutton1.label = Next

# Shutdown Button
shutdown.type = cancelbutton
shutdown.label = Shutdown
"

# Set the images' paths relative to this file's path / 
icon=$(dirname "$0")'/images/det_logo.png'

# Display Pashua's icon
loginconf="$loginconf
img.type = image
img.x = 330
img.y = 250
img.path = $icon"


pashua_run "$loginconf" 'utf8'

#----------------------------------End of First pashuarun--------------------------#





#----------------------------------Define our functions-----------------------------#

# This function Takes the netmask in hex and converts it in to a cidr number ie /21
function bitCountForMask {
    local -i count=0
    local mask="${1##0x}"
    local digit
    while [ "$mask" != "" ]; do
        digit="${mask:0:1}"
        mask="${mask:1}"
        case "$digit" in
            [fF]) count=count+4 ;;
            [eE]) count=count+3 ;;
            [cC]) count=count+2 ;;
            8) count=count+1 ;;
            0) ;;
            *)
                echo 1>&2 "error: illegal digit $digit in netmask"
                return 1
                ;;
        esac
    done
    echo $count
}

# This function takes a netmask in hex and converts it into decimal ie 255.255.248.0
function netmaskconverter {
nh=$netmaskhex
nd=$(($nh % 0x100))
for i in 1 2 3
do
  ((nh = nh / 0x100))
  nd="$((nh % 0x100)).$nd"
done
netmaskdec=$nd # Now we assign this netmask in decimal to a more friendly variable name for use later on
}

#  This function takes 2 arguments. First the IP address ($ipaddr) 
#  and second the subnet in decimal format (netmaskdec) and then pumps out the CIDR Network for the ip/subnet 
netcalc(){
    local IFS='.' ip i
    local -a oct msk
    
    read -ra oct <<<"$1"
    read -ra msk <<<"$2"

    for i in ${!oct[@]}; do
        ip+=( "$(( oct[i] & msk[i] ))" )
    done
    echo "${ip[*]}"
}

choseshutdown()  ## Simple function to handle if the user selects the shutdown button
{
	echo "****************************"
	echo "*  User chose to shutdown  *"
	echo "*  Shuting down..........  *"
	echo "****************************"
	if [ $runmode = "prod" ]
		then
			shutdown -h now
	fi
	exit 0
}

opendeploystudio()
{
	echo "Opening DeployStudio run time application from:- /Applications/Utilities/DeployStudio\ Admin.app/Contents/Applications/DeployStudio\ Runtime.app/Contents/MacOS/DeployStudio\ Runtime.bin"
	if [ $runmode = "prod" ]
		then
			/Applications/Utilities/DeployStudio\ Admin.app/Contents/Applications/DeployStudio\ Runtime.app/Contents/MacOS/DeployStudio\ Runtime.bin & # We run this in the background so we can close strapper. Multitasking Yo!
	fi
}

displaydeploystudio() ## Display the dialog box warning about failed group membership. User must shutdown
{
displayDS=($($CD msgbox --title "Success!" --icon-file $CDRes/images/go.png --text "Great Success!" --no-newline --informative-text "Passing you along to DeployStudio" --button1 "OK"))
echo ""
echo ""
echo "User has passed all checks. Moving them on to DeployStudio"
echo ""
opendeploystudio
}

checkusercreds() ## Function to test user credentials - exits 0 if successful, non zero if a fail
{
/usr/bin/ldapsearch -LLL -H ldap://$domain -x -D $uname@$domain -w $pword -b $sbase sAMAccountName=$uname > /dev/null # This does the auth check and returns the exit codes
# echo $?	
if [ $? -ne "0" ]
	then
	authstatus="Failed"
	echo "******************"
	echo "*  Auth Failed!  *"
	echo "******************"
	echo ""
	echo "Username entered:- $uname"
	echo "Password entered:- $pword"
	echo "-----------------------------------------"
	echo ""
	echo ""
else
	authstatus="Success"
	echo "*********************"
	echo "*  Auth Successful  *"
	echo "*********************"
	echo ""
	echo "Not logging correct user details"
	echo "*--------------------------------*"
	echo ""
	echo ""
	
fi
}

displayfailed() ## Display the dialog box warning about failed login attempt. User can chose to exit here or enter in their details again.
{
failedauth=($($CD msgbox --title "Warning" --icon-file $CDRes/images/stop.png --text "Invalid Credentials" --no-newline --informative-text "Unable to authenticate you against AD.

	Please try again" --button1 "Re-enter Credentials" --button2 "Shutdown"))
	if [ $failedauth = "2" ]
	then 
		choseshutdown
	fi	
}

displaygroupfailed() ## Display the dialog box warning about failed group membership. User must shutdown
{
groupfailed=($($CD msgbox --title "Warning" --icon-file $CDRes/images/stop.png --text "Not a member!" --no-newline --informative-text "Your account is not a member of the
required AD group.

You need to be a member of $ADImagingGroup

Contact central IT Support for assistance" --button1 "Shutdown"))
	if [ $groupfailed = "1" ]
		then
			choseshutdown
	fi
}

displaysitefailed() ## Display the dialogbox warning about failed site lookup from IP Address
{
templogfile=`/usr/bin/mktemp /tmp/sitefailed_XXXXXX` # create a temporary file to dump the user results into.

$CD inputbox --title "Warning" --text "1001" --informative-text "AD Site Name lookup from your IP address has failed.
Or you have indicated that it is incorrect. 
Please provide your 4-digit site code here:" --button1 "Ok" --button2 "Shutdown" > $templogfile

ADSiteCodeEntered=`cat $templogfile | sed -n 2p` # get the site code entered by the user
userbuttonselection=`cat $templogfile | sed -n 1p` # get the value of the button selection

	if [ $userbuttonselection = "2" ]
		then
			choseshutdown
	fi
	echo ""
	echo ""
	echo "Site code entered in manually"
	echo "User entered in site code $ADSiteCodeEntered"
	echo ""
	echo "" # echo out the user input for debug / logging
	displaysitecodesearch  # if the user has entered in their site code and hit ok, then run this function to look up the AD site from their input
}

displaysitefound() ## Display a message letting the user now that we have found their AD site from IP Address - give them a chance to change if this is incorrect
{
sitefound=($($CD msgbox --title "AD Site Found" --icon-file $CDRes/images/go.png --text "AD Site Found:" --no-newline --informative-text "It looks like your AD Site name is:

$ADSiteNameCIDR

Is this correct?" --button1 "Yes" --button2 "No"))
echo ""
echo ""
echo "Found AD Site from CIDR:- $ADSiteNameCIDR"
echo ""
echo ""
	if [ $sitefound = "2" ]
		then
		echo "User has indiated this is incorrect"
		echo "Will let them enter in their own code"
		displaysitefailed # if the user has decided the automatically found AD Site is incorrect then throw them across to the displaysite failed message box and let them enter in the site code
	fi
echo "User has indicated this is the correct site"
}

displaysitecodesearch()
{
ADSiteCodeSearch="(description=$ADSiteCodeEntered*)"
ADSiteNameCode=`/usr/bin/ldapsearch -LLL -H ldap://$domain -x -D $uname@$domain -w $pword -b $sitebase "$ADSiteCodeSearch" siteObject | cut -f 1 -d "," | cut -c 8-`

sitecodefound=($($CD msgbox --title "AD Site Found" --icon-file $CDRes/images/go.png --text "AD Site Found:" --no-newline --informative-text "Based on the site code you entered
I have found the following site:

$ADSiteNameCode

Is this correct?" --button1 "Yes" --button2 "No"))

echo ""
echo "Result of manual site code look up is:- $ADSiteNameCode"
echo ""
if [ $sitecodefound = "2" ]
	then
		displaysitefailed
	fi
}


populateIPvariables()
{
netmaskconverter # Fire off the function to get the hex netmask into a decimal format
cidrcalc=`netcalc $ipaddr $netmaskdec | cut -c 2-` # have to trim off the first . at the start of the output. this gives us our network subnet base 10.128.142.0
netmaskcidr=`bitCountForMask $netmaskhex` # this gives us our CIDR format of our subnet ie /21 for 255.255.248.0
cidr="(cn=$cidrcalc/$netmaskcidr)" # this builds the AD Site CIDR to search for	
}

searchaditems()
{
# Lookup the user's account in AD and show them the friendly name ( AD Attribute:- name )
ADName=`/usr/bin/ldapsearch -LLL -H ldap://$domain -x -D $uname@$domain -w $pword -b $sbase sAMAccountName=$uname | grep -w name | cut -c 7-`

# Find out what groups the user is a member of ( AD Attribute:- memberOf )
ADGroups=`/usr/bin/ldapsearch -LLL -H ldap://$domain -x -D $uname@$domain -w $pword -b $sbase sAMAccountName=$uname | grep memberOf | cut -f 1 -d "," | cut -c 14-`

# Try to find the AD Site name from our network address eg. (cn=10.142.128.0/21)
ADSiteNameCIDR=`/usr/bin/ldapsearch -LLL -H ldap://$domain -x -D $uname@$domain -w $pword -b $sitebase "$cidr" siteObject | grep siteObject | cut -f 1 -d "," | cut -c 16-`

# Echo out these results for debug and logging purposes
echo "Found the following information from AD:"
echo ""
echo "    Your AD name is:- $ADName"
echo "    Your AD Groups are:- 
$ADGroups"
echo "    Your AD Sitename is:- $ADSiteNameCIDR"
echo ""
echo ""
}

#------------------------------End of our functions------------------------------------#



## Lets run some functions now to populate some variables
populateIPvariables

# Do some logic here to authenticate the user - if failed then ask them to retry. Loop until they choose to quit or they get their login correct.
if [ $nextbutton1 = "1" ]
	then
	checkusercreds
	while [ $authstatus = "Failed" ]
	do
	displayfailed
	pashua_run "$loginconf" 'utf8'
	checkusercreds
done
elif [ $shutdown = "1" ]
	then
	choseshutdown
fi

## Ok user is now authenticated yeeewww! Lets run our searchaditems function in order to populate our variables
searchaditems

## Now we need to test the results of our AD Search and see if we are a member of the imaging group
if [[ $ADGroups == *$ADImagingGroup* ]] 
	then
		echo "**"
		echo "Group check successful! You are authorised to deploy."
		echo "**"
else 
displaygroupfailed
fi

## Check to see if we are able to find our AD Site name from our IP Address
if [ -z $ADSiteNameCIDR ]  
then
displaysitefailed
else
displaysitefound
fi

displaydeploystudio

exit 0