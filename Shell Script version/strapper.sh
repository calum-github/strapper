#!/bin/bash

################################################################################################################################
##### Calum Hunter                                                                                                             #
##### 23-09-2014                                                                                                               #
#####                                                                                                                          # 
##### Version 0.3                                                                                                              #
#####                                                                                                                          #
##### Project:      DET NSW - NetBoot Environment Authorization via AD                                                         #
#####                                                                                                                          #
##### Objective:    This script will run at boot on the Netboot Environment image.                                             # 
#####               It will require a user to enter in their AD credentials which will be checked against AD via ldapsearch.   #
#####               If the user provides correct login details and they are in the correct security groups they will be        #
#####               forwarded on to the next stage ie. DeployStudio.                                                           #
################################################################################################################################

# hard coded DET variables
domain="your.domain"         # Our AD domain name
sbase="dc=your,dc=domain"    # Our default search base when searching for user accounts etc
sitebase="CN=Sites,CN=Configuration,DC=your,DC=domain"   # Our search base when looking for Site information only

# The name of the AD Group a user must be a member of in order to image a machine
ADImagingGroup="Some_group"

# Network variables - Get the IP address and the subnet in Hex format
ipaddr=`ifconfig en0 | awk '/inet[ ]/{print $2}'`
netmaskhex=`ifconfig en0 | grep netmask | cut -d' ' -f4`

tput bold
tput setaf 4
echo "*****************************************************"
echo "*                                                   *"
echo "*   Welcome to the Company Mac OS X Deployment Tool *"
echo "*                                                   *"
echo "*****************************************************"
tput sgr0
echo ""
echo ""
echo "In order to continue, please login with your AD username and password"


# Function to check the user credentials - Loop through if invalid credentials provided.
checkusercreds() 
{
# user entered variables
tput bold
echo ""
echo ""
echo "Enter Your Username:-"
tput sgr0
read uname
tput bold
echo ""
echo "Enter Your Password:-"
tput sgr0
read pword
/usr/bin/ldapsearch -LLL -H ldap://$domain -x -D $uname@$domain -w $pword -b $sbase sAMAccountName=$uname > /dev/null
# echo $?
}
checkusercreds
while [ $? -ne "0" ]
do
tput bold
tput setaf 1
echo ""
echo "************************   WARNING   **************************"
echo "*                                                             *"
echo "* Invalid username or password combination! Please try again. *"  
echo "* Ensure that you use your sAMAccount name only.              *"
echo "* Do not appened the @companyname suffix                      *"
echo "*                                                             *"
echo "***************************************************************"
tput sgr0
checkusercreds
done
echo ""
echo ""
tput setaf 4
echo " Authentication Successful! "
tput sgr0


## This function Takes the netmask in hex and converts it in to a cidr number ie /21
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

## This function takes a netmask in hex and converts it into decimal ie 255.255.248.0
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



##  This function takes 2 arguments. First the IP address ($ipaddr) 
##  and second the subnet in decimal format (netmaskdec) and then pumps out the CIDR Network for the ip/subnet 
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
netmaskconverter # Fire off the function to get the hex netmask into a decimal format
cidrcalc=`netcalc $ipaddr $netmaskdec | cut -c 2-` # have to trim off the first . at the start of the output. this gives us our network subnet base 10.128.142.0
netmaskcidr=`bitCountForMask $netmaskhex` # this gives us our CIDR format of our subnet ie /21 for 255.255.248.0

##  Now build the AD Site network subnet variable
##  We try to match this to a Site in AD
cidr="(cn=$cidrcalc/$netmaskcidr)"

## Lets do some AD lookups
# Lookup the user's account in AD and show them the friendly name ( AD Attribute:- name )
ADName=`/usr/bin/ldapsearch -LLL -H ldap://$domain -x -D $uname@$domain -w $pword -b $sbase sAMAccountName=$uname | grep -w name | cut -c 7-`

# Find out what groups the user is a member of ( AD Attribute:- memberOf )
ADGroups=`/usr/bin/ldapsearch -LLL -H ldap://$domain -x -D $uname@$domain -w $pword -b $sbase sAMAccountName=$uname | grep memberOf | cut -f 1 -d "," | cut -c 14-`

# Try to find the AD Site name from our network address eg. (cn=10.142.128.0/21)
ADSiteNameCIDR=`/usr/bin/ldapsearch -LLL -H ldap://$domain -x -D $uname@$domain -w $pword -b $sitebase "$cidr" siteObject | grep siteObject | cut -f 1 -d "," | cut -c 16-`


tput setaf 4
echo ""
echo ""
echo " Your AD friendly name is:- $ADName"
echo ""
echo " You are a member of the following groups: "
echo ""
tput setaf 2
echo "$ADGroups "
echo ""
tput setaf 4
echo " In order to image you need to be a member of:- $ADImagingGroup"

if [[ $ADGroups == *$ADImagingGroup* ]] ## Check if the list of groups the user is a member of contains the name of the group we require in order to image
then
echo ""
echo " Checking.................."
echo ""
echo " Group check successful! You are authorised to deploy."
echo ""
else 
echo ""
tput setaf 1
echo "*****************  WARNING  ****************"
echo "* DAMN! Looks like you are NOT a member!!  *"
echo "* You are not authorised to deploy         *"
echo "* Contact central IT for support           *"
echo "********************************************"
tput sgr0
exit 1
fi


if [ -z $ADSiteNameCIDR ]   # Check to see if we were able to find the AD Site name via our network address
then
tput bold
tput setaf 1
echo "**********************************************************    WARNING    **********************************************************"
echo "*                                                                                                                                 *"
echo "* Your AD Site could not be found automatically! Perhaps your calculated Network CIDR is incorrect!                               *"
echo "* I have calculated your IP address as $ipaddr with subnet $netmaskdec which means your Network CIDR is $cidrcalc/$netmaskcidr   *"
echo "* Instead we will have to use your site code.                                                                                     *"
echo "*                                                                                                                                 *"
echo "***********************************************************************************************************************************"
tput sgr0
# Get the site code from the user if required
echo ""
tput bold
echo "Please enter your 4 digit AD site code:-"
tput sgr0
read ADSiteCodeEntered
# Lookup the site name from the site code entered
ADSiteCodeSearch="(description=$ADSiteCodeEntered*)"
ADSiteNameCode=`/usr/bin/ldapsearch -LLL -H ldap://$domain -x -D $uname@$domain -w $pword -b $sitebase "$ADSiteCodeSearch" siteObject | cut -f 1 -d "," | cut -c 8-`
echo ""
echo ""
tput setaf 4
echo "******************************************************************************"
echo "*                                                                            *"
echo "*          Based on your site code your site is $ADSiteNameCode              *"
echo "*                                                                            *"
echo "******************************************************************************"
tput sgr0
else
# Try to find the AD Site CODE from our SiteName
ad_site_name="(cn=$ADSiteNameCIDR*)"
ADSiteCodeLookedUp=`/usr/bin/ldapsearch -LLL -H ldap://$domain -x -D $uname@$domain -w $pword -b $sitebase "$ad_site_name" description | grep description | cut -c 14- | cut -f1 -d ","`

tput setaf 4
echo "******************************************************************************"
echo "*                                                                            *"
echo "*       Your AD Site name from AD CIDR network $cidr is $ADSiteNameCIDR      *"
echo "*                                                                            *"
echo "******************************************************************************"
echo " I also found your site code from your Site Name to be $ADSiteCodeLookedUp"
tput sgr0
fi
tput setaf 4
echo ""
echo ""
echo ""
echo "******************************************************************************"
echo "*                                                                            *"
echo "*               Passing you along to DeployStudio.............               *"
echo "*                                                                            *"
echo "******************************************************************************"
tput sgr0

exit 0