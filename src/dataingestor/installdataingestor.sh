#!/bin/bash -ex

# variables that must be set beforehand
#NODE_PREFIX=avereclient
#NODE_COUNT=3
#LINUX_USER=azureuser
#AVEREVFXT_NODE_IPS="172.16.1.8,172.16.1.9,172.16.1.10"
#
# called like this:
#  sudo NODE_PREFIX=avereclient NODE_COUNT=3 LINUX_USER=azureuser AVEREVFXT_NODE_IPS="172.16.1.8,172.16.1.9,172.16.1.10" ./install.sh
#
function retrycmd_if_failure() {
    retries=$1; wait_sleep=$2; timeout=$3; shift && shift && shift
    for i in $(seq 1 $retries); do
        timeout $timeout ${@}
        [ $? -eq 0  ] && break || \
        if [ $i -eq $retries ]; then
            echo Executed \"$@\" $i times;
            return 1
        else
            sleep $wait_sleep
        fi
    done
    echo Executed \"$@\" $i times;
}

function apt_get_update() {
    retries=10
    apt_update_output=/tmp/apt-get-update.out
    for i in $(seq 1 $retries); do
        timeout 120 apt-get update 2>&1 | tee $apt_update_output | grep -E "^([WE]:.*)|([eE]rr.*)$"
        [ $? -ne 0  ] && cat $apt_update_output && break || \
        cat $apt_update_output
        if [ $i -eq $retries ]; then
            return 1
        else sleep 30
        fi
    done
    echo Executed apt-get update $i times
}

function apt_get_install() {
    retries=$1; wait_sleep=$2; timeout=$3; shift && shift && shift
    for i in $(seq 1 $retries); do
        # timeout occasionally freezes
        #echo "timeout $timeout apt-get install --no-install-recommends -y ${@}"
        #timeout $timeout apt-get install --no-install-recommends -y ${@}
        apt-get install --no-install-recommends -y ${@}
        echo "completed"
        [ $? -eq 0  ] && break || \
        if [ $i -eq $retries ]; then
            return 1
        else
            sleep $wait_sleep
            apt_get_update
        fi
    done
    echo Executed apt-get install --no-install-recommends -y \"$@\" $i times;
}

function config_linux() {
	export DEBIAN_FRONTEND=noninteractive  
	apt_get_update
	apt_get_install 20 10 180 nfs-common parallel
}

function mount_avere() {
    COUNTER=1
    for VFXT in $(echo $AVEREVFXT_NODE_IPS | sed "s/,/ /g")
    do
        MOUNT_POINT="/nfs/node${COUNTER}"
        echo "Mounting to $VFXT:msazure to ${MOUNT_POINT}"
        sudo mkdir -p $MOUNT_POINT
        # no need to write again if it is already there
        if grep -v --quiet $VFXT /etc/fstab; then
            echo "$VFXT:/msazure	${MOUNT_POINT}	nfs hard,nointr,proto=tcp,mountproto=tcp,retry=30 0 0" >> /etc/fstab
            sudo mount ${MOUNT_POINT}
        fi
        COUNTER=$(($COUNTER + 1))
    done
}

function write_parallelcp() {
    FILENAME=/usr/bin/parallelcp
    sudo touch $FILENAME
    sudo chmod 755 $FILENAME
    sudo /bin/cat <<EOM >$FILENAME
#!/bin/bash

display_usage() { 
    echo -e "\nUsage: \$0 SOURCE_DIR DEST_DIR\n" 
} 

if [  \$# -le 1 ] ; then 
    display_usage
    exit 1
fi 
 
if [[ ( \$# == "--help") ||  \$# == "-h" ]] ; then 
    display_usage
    exit 0
fi 

SOURCE_DIR="\$1"
DEST_DIR="\$2"

if [ ! -d "\$SOURCE_DIR" ] ; then
    echo "Source directory \$SOURCE_DIR does not exist, or is not a directory"
    display_usage
    exit 2
fi

if [ ! -d "\$DEST_DIR" ] && ! mkdir -p \$DEST_DIR ; then
    echo "Destination directory \$DEST_DIR does not exist, or is not a directory"
    display_usage
    exit 2
fi

if [ ! -w "\$DEST_DIR" ] ; then
    echo "Destination directory \$DEST_DIR is not writeable, or is not a directory"
    display_usage
    exit 3
fi

if ! which parallel > /dev/null ; then
    sudo apt-get update && sudo apt install -y parallel
fi

DIRJOBS=225
JOBS=225
find \$SOURCE_DIR -mindepth 1 -type d -print0 | sed -z "s/\$SOURCE_DIR\///" | parallel --will-cite -j\$DIRJOBS -0 "mkdir -p \$DEST_DIR/{}"
find \$SOURCE_DIR -mindepth 1 ! -type d -print0 | sed -z "s/\$SOURCE_DIR\///" | parallel --will-cite -j\$JOBS -0 "cp -P \$SOURCE_DIR/{} \$DEST_DIR/{}"
EOM
}

function write_msrsync() {
    # install this from https://github.com/jbd/msrsync
    FILENAME=/usr/bin/msrsync
    sudo touch $FILENAME
    sudo chmod 755 $FILENAME
    sudo wget -O $FILENAME https://raw.githubusercontent.com/jbd/msrsync/master/msrsync
    sudo chmod +x $FILENAME

    PRIMEFILE=/usr/bin/prime.py
    sudo wget -O $PRIMEFILE https://raw.githubusercontent.com/Azure/Avere/master/src/dataingestor/prime.py
    sudo chmod +x $PRIMEFILE
}

function main() {
    echo "config Linux"
    config_linux
    echo "mount avere"
    mount_avere
    echo "write parallelcp"
    write_parallelcp
    echo "install msrsync"
    write_msrsync
    echo "installation complete"
}

main