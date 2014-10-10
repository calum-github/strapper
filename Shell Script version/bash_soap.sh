#!/bin/bash

########################################################################################
## 																				      ##	
## Script to pull information about building, room and level via SOAP                 ##
##                                                                                    ##
## Author: Calum Hunter                                                               ##  
## 08-10-2014                                                                         ##
##                                                                                    ##
## Version 0.1                                                                        ## 
##                                                                                    ##
########################################################################################

## Fair warning - this code is horrible and there is huge duplication don't judge me!

echo "Making SOAP from BASH Yeeew"
echo "Please enter in some details so we can get the infos"
echo ""
echo "Please enter your site code"
read sitecode
echo ""
echo ""

# Header of our Get buildings envelope
buildings1="$(cat <<'ENDOFVAR'
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:web="http://udmblr.dtmanagement.det.nsw.edu.au/Webservices/">
   <soapenv:Header/>
   <soapenv:Body>
      <web:GetBuildingsBySiteCode>
         <web:SiteCode>
ENDOFVAR)"

# Footer of our buildings envelope
buildings2="$(cat <<'ENDOFVAR'
</web:SiteCode>
      </web:GetBuildingsBySiteCode>
   </soapenv:Body>
</soapenv:Envelope>
ENDOFVAR)"


# Build our buildings envelope and include our site code
getbuildings_soap_envelope="$buildings1""$sitecode""$buildings2"

# make a temporary file on disk to store our results
buildingresults=`/usr/bin/mktemp /tmp/buildings_XXX` 	

# Post our BUILDINGS envelope and write the output into our BUILDINGS results file
curl -H "Content-type: text/xml; charset=utf-8" -H "SOAPAction:" -d "$getbuildings_soap_envelope" -X POST http://udmblr.dtmanagement.det.nsw.edu.au/locale.asmx > $buildingresults


# This is our XML Parser Function
read_dom() {
	local IFS=\>  ## Make IFS (Input Field Separator) local to this function, make the text split on > instead of spaces or tabs
	read -d \< TAG RESULT # read content from stdin, split text via IFS and assign to variables Entity and Content
}


# This loops through our buildingresults and displays our output nicely
while read_dom; do	
	if [[ $TAG = "GetBuildingsBySiteCodeResult" ]]; then
		echo ""
		echo ""
		echo ""
		echo "The following BUILDINGS are available..."
		echo ""
		echo $RESULT
		echo $RESULT > /tmp/Available_Buildings.txt
		echo "" 
		echo ""
	fi 
done < $buildingresults


echo "Please enter your building code"
read buildingcode
echo ""
echo ""


# Header of our Levels envelope
levels1="$(cat <<'ENDOFVAR'
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:web="http://udmblr.dtmanagement.det.nsw.edu.au/Webservices/">
   <soapenv:Header/>
   <soapenv:Body>
      <web:GetLevelsByBuilding>
         <web:SiteCode>
ENDOFVAR)"


# Footer of our Levels envelope
levels2="$(cat <<'ENDOFVAR'
</web:SiteCode>
	<web:BuildingCode>
ENDOFVAR)"

levels3="$(cat <<'ENDOFVAR'
</web:BuildingCode>
		</web:GetLevelsByBuilding>
	</soapenv:Body>
</soapenv:Envelope>
ENDOFVAR)"


# Build our buildings envelope and include our site code
getlevels_soap_envelope="$levels1""$sitecode""$levels2""$buildingcode""$levels3"

# make a temporary file on disk to store our results
levelsresults=`/usr/bin/mktemp /tmp/levels_XXX` 	


# Post our LEVELS envelope and write the output into our Levels results file
curl -H "Content-type: text/xml; charset=utf-8" -H "SOAPAction:" -d "$getlevels_soap_envelope" -X POST http://udmblr.dtmanagement.det.nsw.edu.au/locale.asmx > $levelsresults


# This loops through our LEVELS Results and displays our output nicely
while read_dom; do	
	if [[ $TAG = "GetLevelsByBuildingResult" ]]; then
		echo ""
		echo ""
		echo ""
		echo "The following LEVELS are available..."
		echo ""
		echo $RESULT
		echo $RESULT > /tmp/Available_Levels.txt
		echo "" 
		echo ""
	fi 
done < $levelsresults



echo "Please enter your LEVEL code"
read levelcode
echo ""
echo ""


# Header of our ROOMS envelope
rooms1="$(cat <<'ENDOFVAR'
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:web="http://udmblr.dtmanagement.det.nsw.edu.au/Webservices/">
   <soapenv:Header/>
   <soapenv:Body>
      <web:GetRoomsByLevel>
         <web:SiteCode>
ENDOFVAR)"


# Footer of our Levels envelope
rooms2="$(cat <<'ENDOFVAR'
</web:SiteCode>
	<web:BuildingCode>
ENDOFVAR)"

rooms3="$(cat <<'ENDOFVAR'
</web:BuildingCode>
		<web:Level>
ENDOFVAR)"

rooms4="$(cat <<'ENDOFVAR'
</web:Level>
	</web:GetRoomsByLevel>
	</soapenv:Body>
</soapenv:Envelope>
ENDOFVAR)"


# Build our Rooms envelope and include our site code
getrooms_soap_envelope="$rooms1""$sitecode""$rooms2""$buildingcode""$rooms3""$levelcode""$rooms4"

# make a temporary file on disk to store our results
roomsresults=`/usr/bin/mktemp /tmp/rooms_XXX` 	


# Post our LEVELS envelope and write the output into our Levels results file
curl -H "Content-type: text/xml; charset=utf-8" -H "SOAPAction:" -d "$getrooms_soap_envelope" -X POST http://udmblr.dtmanagement.det.nsw.edu.au/locale.asmx > $roomsresults


# This loops through our buildingresults and displays our output nicely
while read_dom; do	
	if [[ $TAG = "GetRoomsByLevelResult" ]]; then
		echo ""
		echo ""
		echo ""
		echo "The following ROOMS are available..."
		echo ""
		echo $RESULT
		echo $RESULT > /tmp/Available_Rooms.txt
		echo "" 
		echo ""
	fi 
done < $roomsresults


echo "Please choose your ROOM code"
read roomcode
echo ""
echo ""
echo "based on this information you have chosen:"
echo "Site:          $sitecode"
echo "Building:      $buildingcode"
echo "Level:         $levelcode"
echo "Room:          $roomcode"


exit 0