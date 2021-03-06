#!/bin/sh

URL="https://plex.tv/downloads?channel=plexpass"
DOWNLOADPATH="/tmp"
PMSPARENTPATH="/usr/pbi/plexmediaserver-amd64/share"
PMSLIVEFOLDER="plexmediaserver"
PMSBAKFOLDER="plexmediaserver.bak"
PMSPATTERN="PlexMediaServer-[0-9]*.[0-9]*.[0-9]*.[0-9]*.[0-9]*-[0-9,a-f]*-freebsd-amd64.tar.bz2"
CERTFILE="/usr/local/share/certs/ca-root-nss.crt"
AUTOUPDATE=0
FORCEUPDATE=0
VERBOSE=0
REMOVE=0

# Initialize CURRENTVER to the script max so if reading the current version fails
# for some reason we don't blindly clobber things
CURRENTVER=9999.9999.9999.9999.9999


usage()
{
cat << EOF
usage: $0 options

This script will search the plex.tv download site for a download link
and if it is newer than the currently installed version the script will
download and optionaly install the new version.

OPTIONS:
   -u      PlexPass username
             If -u is specified without -p then the script will
             prompt the user to enter the password when needed
   -p      PlexPass password
   -c      PlexPass user/password file
             When wget is run with username and password on the
             command line, that information is displayed in the
             process list for all to see.  A more secure method
             is to create a file readable only by root that is
             formatted like this:
               user={Your Username Here}
               password={Your Password Here}
   -l      Local file to install instead of latest from Plex.tv
   -d      download folder (default /tmp) Ignored if -l is used
   -a      Auto Update to newer version
   -f      Force Update even if version is not newer
   -r      Remove update packages older than current version
             Done before any update actions are taken.
   -v      Verbose
EOF
}


##  verNum()
##  READS:    $1 (passed in string)
##  MODIFIES: NONE
##
##  Converts the Plex version string to a mathmatically comparable
##      number by removing non numericals and padding each section with zeros
##      so v0.9.9.10.485 becomes 00000009000900100485
verNum()
{
    echo "$@" | awk -F. '{ printf("%04d%04d%04d%04d%04d", $1,$2,$3,$4,$5)}'
}


##  removeOlder()
##  READS:    $DOWNLOADPATH $PMSPATTERN $CURRENTVER
##  MODIFIES: NONE
##
##  Searches $DOWNLOADPATH for PMS install packages and removes versions older
##  than $CURRENTVER
removeOlder()
{
    for FOUNDINSTALLFILE in `ls $DOWNLOADPATH/$PMSPATTERN`
    do {
        if [ $(verNum `basename $FOUNDINSTALLFILE`) -lt $(verNum $CURRENTVER) ]; then {
            if [ $VERBOSE = 1 ]; then echo Removing $FOUNDINSTALLFILE; fi
            rm -f $FOUNDINSTALLFILE
        } fi
    } done
}


##  webGet()
##  READS:    $1 (URL) $DOWNLOADPATH $USERPASSFILE $USERNAME $PASSWORD $VERBOSE
##  MODIFIES: NONE
##
##  invoke wget with configured account info
webGet()
{
    local LOGININFO=""
    local QUIET="--quiet"

    if [ ! "x$USERPASSFILE" = "x" ] && [ -e $USERPASSFILE ]; then
        LOGININFO="--config=$USERPASSFILE"
    elif [ ! "x$USERNAME" = "x" ]; then
        if [ "x$PASSWORD" = "x" ]; then
            LOGININFO="--http-user=$USERNAME --ask-password"
        else
            LOGININFO="--http-user=$USERNAME --http-password=$PASSWORD"
        fi
    fi

    if [ $VERBOSE = 1 ]; then QUIET=""; fi
    wget $QUIET $LOGININFO --auth-no-challenge --ca-certificate=$CERTFILE --timestamping --directory-prefix="$DOWNLOADPATH" "$1"
    if [ $? -ne 0 ]; then {
        echo Error downloading $1
        exit 1
    } fi
}


##  findLatest()
##  READS:    $URL $DOWNLOADPATH $PMSPATTERN $VERBOSE
##  MODIFIES: $DOWNLOADURL
##
##  connects to the Plex.tv download site and scrapes for the latest download link
findLatest()
{
    local SCRAPEFILE=`basename $URL`

    webGet "$URL" || exit $?
    if [ $VERBOSE = 1 ]; then echo -n Searching $URL for $PMSPATTERN .....; fi
    DOWNLOADURL=`grep -o "http:.*$PMSPATTERN" "$DOWNLOADPATH/$SCRAPEFILE"`
    if [ "x$DOWNLOADURL" = "x" ]; then {
        # DOWNLOADURL is zero length, i.e. nothing matched PMSPATTERN. Error and exit
        echo Could not find a $PMSPATTERN download link on page $URL
        exit 1
    } else {
        if [ $VERBOSE = 1 ]; then echo Done.; fi
    } fi
}


##  applyUpdate()
##  READS:    $PMSPARENTPATH $PMSLIVEFOLDER $PMSBAKFOLDER $LOCALINSTALLFILE
##  MODIFIES: NONE
##
##  Removes anything in the specified backup location, stops
##    Plex, moves the current to backup, then tries to extract the new zip
##    to the live location.  If there is an error while unpacking the files
##    are deleted and the backup is moved back.  Plex is then started.
##    It could be possible to check status after starting a new plex and
##    rolling back if it does not start, should check that it is running
##    properly before hand to avoid constantly trying to update a broken
##    install
applyUpdate()
{
    if [ $VERBOSE = 1 ]; then echo -n Removing previous PMS Backup .....; fi
    rm -rf $PMSPARENTPATH/$PMSBAKFOLDER
    if [ $VERBOSE = 1 ]; then echo Done.; fi
    if [ $VERBOSE = 1 ]; then echo -n Stopping Plex Media Server .....; fi
    service plexmediaserver stop
    if [ $VERBOSE = 1 ]; then echo Done.; fi
    if [ $VERBOSE = 1 ]; then echo -n Moving current Plex Media Server to backup location .....; fi
    mv $PMSPARENTPATH/$PMSLIVEFOLDER/ $PMSPARENTPATH/$PMSBAKFOLDER/
    if [ $VERBOSE = 1 ]; then echo Done.; fi
    if [ $VERBOSE = 1 ]; then echo -n Extracting $LOCALINSTALLFILE .....; fi
    mkdir $PMSPARENTPATH/$PMSLIVEFOLDER/
    tar -xj --strip-components 1 --file $LOCALINSTALLFILE --directory $PMSPARENTPATH/$PMSLIVEFOLDER/
    if [ $? -ne 0 ]; then {
        echo Error exctracting $LOCALINSTALLFILE. Rolling back to previous version.
        rm -rf $PMSPARENTPATH/$PMSLIVEFOLDER/
        mv $PMSPARENTPATH/$PMSBAKFOLDER/ $PMSPARENTPATH/$PMSLIVEFOLDER/
    } else {
        if [ $VERBOSE = 1 ]; then echo Done.; fi
    } fi
    if [ $VERBOSE = 1 ]; then echo -n Starting Plex Media Server .....; fi
    service plexmediaserver start
    if [ $VERBOSE = 1 ]; then echo Done.; fi
}

while getopts x."u:p:c:l:d:afvr" OPTION
do
     case $OPTION in
         u) USERNAME=$OPTARG ;;
         p) PASSWORD=$OPTARG ;;
         c) USERPASSFILE=$OPTARG ;;
         l) LOCALINSTALLFILE=$OPTARG ;;
         d) DOWNLOADPATH=$OPTARG ;;
         a) AUTOUPDATE=1 ;;
         f) FORCEUPDATE=1 ;;
         v) VERBOSE=1 ;;
         r) REMOVE=1 ;;
         ?) usage; exit 1 ;;
     esac
done

# Get the current version
CURRENTVER=`export LD_LIBRARY_PATH=$PMSPARENTPATH/$PMSLIVEFOLDER; $PMSPARENTPATH/$PMSLIVEFOLDER/Plex\ Media\ Server --version`
if [ $REMOVE = 1 ]; then removeOlder; fi

if [ "x$LOCALINSTALLFILE" = "x" ]; then {
    #  No local source provided, check the web
    findLatest || exit $?
    if [ $FORCEUPDATE = 1 ] || [ $(verNum `basename $DOWNLOADURL`) -gt $(verNum $CURRENTVER) ]; then {
        webGet "$DOWNLOADURL"  || exit $?
        LOCALINSTALLFILE="$DOWNLOADPATH/`basename $DOWNLOADURL`"
    } else {
        if [ $VERBOSE = 1 ]; then echo Already running latest version $CURRENTVER; fi
        exit
    } fi
} elif [ ! $FORCEUPDATE = 1 ] &&  [ $(verNum `basename $LOCALINSTALLFILE`) -le $(verNum $CURRENTVER) ]; then {
    if [ $VERBOSE = 1 ]; then echo Already running version $CURRENTVER; fi
    if [ $VERBOSE = 1 ]; then echo Use -f to force install $LOCALINSTALLFILE; fi
    exit
} fi


# If either update flag is set then verify archive integrity and install
if [ $FORCEUPDATE = 1 ] || [ $AUTOUPDATE = 1 ]; then {
    if [ $VERBOSE = 1 ]; then echo -n Verifying $LOCALINSTALLFILE .....; fi
    bzip2 -t $LOCALINSTALLFILE
    if [ $? -ne 0 ]; then {
        echo $LOCALINSTALLFILE is not a valid archive, cannot update with this file.
    } else {
        if [ $VERBOSE = 1 ]; then echo Done; fi
        applyUpdate
    } fi
} fi
