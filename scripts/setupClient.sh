#!/bin/bash
cd $(dirname "$0")/..
keyHost=$1
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi
if [ -z $keyHost ] ; then
	echo "Usage: $0 user@keyserver"
	exit 0
fi
echo "Backing up current initrd"
cp /initrd.img /boot/initrd.img.cryptbootbackup
echo "Setting up Key-Server at $1"
apt-get install busybox dropbear
echo "Which ethernet interface is to be used on boot?"
echo "ATTENTION! eth0 is not default anymore. Check ifconfig if unsure"
read IF
echo "Enable DHCP? (y/n)"
read DHCP
if [ "$DHCP" == y ] ; then
	IPCONFIG=":::::$IF:dhcp"
else
	echo "What is the IP for this PC?"
	read IP
	echo "What is the gateway? (e.g. router)"
	read GW
	IPCONFIG="$IP::$GW:255.255.255.0::$IF"
fi
echo "
BUSYBOX=y
DROPBEAR=y
DEVICE=$IF
IP=$IPCONFIG" >> /etc/initramfs-tools/initramfs.conf

echo "
CRYPTSETUP=y" >> /etc/cryptsetup-initramfs/conf-hook

# Generate ssh key to retrieve keyfile with
mkdir -p /etc/initramfs-tools/root/.ssh
ssh-keygen -t rsa -f /etc/initramfs-tools/root/.ssh/unlock_rsa -N ''
# Installing initramfs hooks to ensure that the required files are available during boot.
cp client/ssh-client /etc/initramfs-tools/hooks/
cp client/unlock-keys /etc/initramfs-tools/hooks/unlock-keys
# Installing cryptsetup keyscript
cp client/get_key_ssh /lib/cryptsetup/scripts/get_key_ssh 
# Mark scripts as executable
chmod +x /etc/initramfs-tools/hooks/ssh-client
chmod +x /etc/initramfs-tools/hooks/unlock-keys
chmod a+x /lib/cryptsetup/scripts/get_key_ssh 
# Adjust ip address.
sed -i "s/KEYHOST_ADDRESS/$keyHost/g" /lib/cryptsetup/scripts/get_key_ssh
# Adjust interface.
sed -i "s/PLACEHOLDER_FOR_IF/$IF/g" /lib/cryptsetup/scripts/get_key_ssh
# Create and mount tmpfs (to not leave traces on any filesystem).
mkdir tmp-mount && mount -t tmpfs none ./tmp-mount
# Waiting for user to authorize the new RSA key
echo "Please add this key to authorized_keys on $keyHost"
echo "Press enter when finished"
echo "command=\"sh ./crypt-scripts/retrieve_"$HOSTNAME"_key\" `cat /etc/initramfs-tools/root/.ssh/unlock_rsa.pub`"
read
# Retrieve proper MAC address
mac=$(cat /sys/class/net/$IF/address)
# Retrieve keyfile
ssh $keyHost -i /etc/initramfs-tools/root/.ssh/unlock_rsa -o UserKnownHostsFile=/etc/initramfs-tools/root/.ssh/known_hosts "$mac" > ./tmp-mount/keyfile
# Verify keyfile
echo "Please verify this hash for the keyfile to be correct. Abort, if they differ! (ecf255377f0f44003b40897ca41696c82fbe25dd would mean that MAC-Address verification has failed.)"
sha1sum ./tmp-mount/keyfile | cut -d' ' -f1
read

echo "What is the path of the physical encrypted root partition? (e.g. /dev/sda1)"
read PART
# Add key to crypto device.
cryptsetup luksAddKey $PART ./tmp-mount/keyfile
echo "What is the name of the cryptvolume? (e.g. sda2_crypt)"
read CRYPTNAME
sed -i "/$CRYPTNAME/s/$/,keyscript=\/lib\/cryptsetup\/scripts\/get_key_ssh/" /etc/crypttab

update-initramfs -u -k all
