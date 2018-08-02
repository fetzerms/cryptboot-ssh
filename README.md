# cryptboot-ssh
These scripts enable unlocking of a crypted root device at boot time, using ssh. During the boot, the encrypted client establishes a ssh connection to the key server and retrieves the required keyfiles using SSH pubkey authentication. As another layer of security the clients MAC-Address is used to authorize the key retrieval.

These scripts have been tested under the following distributions:

| Distribution | Version | Who? | When?
| ------- | ----- | -------- | ------- |
| Ubuntu Server | 16.04.2 | [fetzerms](https://github.com/fetzerms/) | 2017-04-30 |
| Ubuntu Server | 14.04.3 | [fetzerms](https://github.com/fetzerms/) | 2015-11-13 |
| Debian | 8.2 | [fetzerms](https://github.com/fetzerms/) | 2015-11-10 |
| Debian | 7.9 | [fetzerms](https://github.com/fetzerms/) | unknown |
| Raspbian | 7.11 | [459below](https://github.com/459below/) | 2016-08-17 |


These scripts are currently **not** working with the following distributions:

| Distribution | Version | Who? | When?
| ------- | ----- | -------- | ------- |
| Debian | 9.4 | [sscheib](https://github.com/sscheib/) | 2018-03-18 |


Feel free to add yourself (and your distribution) to this list!

## Terms
 * "Key server" - A (virtual) machine serving the encryption keys via ssh.
 * "Client" - A (virtual) machine, retrieving the encryption keys at boot time.

## Repository contents
 *  ./client  - Scripts and hooks to be deployed on the client.
 *  ./server  - Scripts to be deployed on the key server
 *  ./scripts - Scripts to automate the setup of clients and servers. Needs some rework. Currently the manual setup is highly recommended.
 *  README.md - This readme file.
 *  LICENSE - The GPLv2 license.
 
## Security considerations

 * The "Key server" should be under your full control. Hosting on a rented VPS is not recommended.
 * The "Key server" should only be reachable from the clients ips.
 * The "Key server" should only be turned on when needed.
 * A compromised Key server may reveal all crypt keys.

## Todos
 * Wrapper scripts on client and server side to require the least user input.
 * Some logging of the key retrievals.
 * Some IRC logging of the retrievals using IRCCatX

## Usage 

The following chapter describes the usage of the scripts. It is recommended that you read through all the steps and make sure to understand every single step before actually implementing it.

### Caution

Testing this on a virtual machine is recommended. If any errors occour during the setup, the encrypted system may not be bootable anymore. Please make sure that you backup your machine prior to using these scripts. If you plan to use this on a bare metal machine, KVM over IP access is recommended.

### Prerequisites

This example assumes two freshly installed virtual debian 8.0.2 netinstall machines, with sshd running. The cryptvm is installed using "**Encrypted-LVM**" from the debian installer. Both machines can reach each other via ssh.

| Name | Ip | Mac | Role |
| ------- | ----- | -------- | ------- |
| cryptvm | 192.168.1.201 | 08:00:27:8b:ff:f9 | Client |
| keyvm | 192.168.1.245 | does not matter | Key Server |

Please note this information for your own servers.

### Preparation

This tutorial uses shell variables to offer a more generic approach. In case you close the terminals you are working in, please make sure to set the variables again. Always double check the result of your operation.

### Key server setup

These steps are executed on the **keyvm**. As mentioned above, variables are used. If you close your terminal and decide to resume the setup, make sure to set these variables *again*. If you decide to add a second client, make sure to use a different client name.

```bash
user@keyvm:~$ clientName="cryptvm"
user@keyvm:~$ clientMac="08:00:27:8b:ff:f9"
```
The following command prepares the required directories. This step is only required for the initial setup.

```bash
user@keyvm:~$ mkdir crypt-{keys,scripts}
user@keyvm:~$ mkdir .ssh
```

The following steps are client specific and need to be executed for each client.

```bash
# Generate a random keyfile for $clientName
user@keyvm:~$ dd bs=512 count=4 if=/dev/urandom of=./crypt-keys/"$clientName".keyfile iflag=fullblock 

# Download the server-keyscript and make it executable
user@keyvm:~$ wget https://raw.githubusercontent.com/fetzerms/cryptboot-ssh/master/server/retrieve_crypto_key -O ./crypt-scripts/retrieve_"$clientName"_key
user@keyvm:~$ chmod +x ./crypt-scripts/retrieve_"$clientName"_key

# Adjust variables in key script.
user@keyvm:~$ sed -i "s/PLACEHOLDER_FOR_MAC_ADDRESS/$( echo "${clientMac^^}" | sha1sum | awk '{ print $1 }')/g" ./crypt-scripts/retrieve_"$clientName"_key
user@keyvm:~$ sed -i "s/PLACEHOLDER_FOR_KEYFILE/"$clientName"/g" ./crypt-scripts/retrieve_"$clientName"_key
```

The next required steps need to be done on the client. Please leave your Keyserver terminal open (or make sure to set the variables again).

### Client setup

These steps are executed on the **cryptvm**. All commands are executed as **root**. Variables are used (I won't stress this no more...).

Variables:
```bash
# Set username and ip of the keyvm.
root@cryptvm:~$ keyHost="privat@192.168.1.245"

# Set own mac address.
root@cryptvm:~$ mac=$(ifconfig | grep HWaddr | awk '{ print $NF }')
```

The following step is Debian specific and may need to be adjusted in other distributions

```bash
# Install busybox and dropbear.
root@cryptvm:~$ apt-get install busybox dropbear
```

You may copy the keys from the dropbear installation. This will allow you to connect via ssh in case the system remains unbootable.

Edit /etc/initramfs-tools/initramfs.conf to include busybox and assign an ip during boot time. You may also use dhcp. Please refer to the documentation.
```bash
BUSYBOX=y
DROPBEAR=y
DEVICE=eth0
IP=192.168.1.201::192.168.1.1:255.255.255.0::eth0
CRYPTSETUP=y
```

```bash
# Generate ssh key to retrieve keyfile with
root@cryptvm:~$ mkdir -p /etc/initramfs-tools/root/.ssh/
root@cryptvm:~$ ssh-keygen -t rsa -f /etc/initramfs-tools/root/.ssh/unlock_rsa -N ''

# Download initramfs hooks to ensure that the required files are available during boot.
root@cryptvm:~$ wget https://raw.githubusercontent.com/fetzerms/cryptboot-ssh/master/client/ssh-client -O /etc/initramfs-tools/hooks/ssh-client
root@cryptvm:~$ wget https://raw.githubusercontent.com/fetzerms/cryptboot-ssh/master/client//unlock-keys -O /etc/initramfs-tools/hooks/unlock-keys

# Enable the hooks (make them executable)
root@cryptvm:~$ chmod +x /etc/initramfs-tools/hooks/ssh-client
root@cryptvm:~$ chmod +x /etc/initramfs-tools/hooks/unlock-keys

# Download cryptsetup keyscript and mark as executable
root@cryptvm:~$ wget https://raw.githubusercontent.com/fetzerms/cryptboot-ssh/master/client/get_key_ssh -O /lib/cryptsetup/scripts/get_key_ssh 
root@cryptvm:~$ chmod a+x /lib/cryptsetup/scripts/get_key_ssh 

# Adjust ip address.
root@cryptvm:~$ sed -i "s/KEYHOST_ADDRESS/$keyHost/g" /lib/cryptsetup/scripts/get_key_ssh
```

After these steps, make sure to copy the contents of unlock_rsa.pub to your clipboard.

### Adding pubkeys to the keyvm

These steps are executed on the **keyvm**. Variables are used.

```bash
# Add the generated pubkey (from cryptvm) to the keyvm. 
# Make sure to adjust "<<copied_unlock.rsa>>". This includes the ssh-rsa and root@host portion.
# The command option enforces the connecting client to only execute a specific command, which
# will be the command to retrieve the crypt key. Other commands or interactive sessions are not 
# possible with this key.
user@keyvm:~$ echo "command=\"./crypt-scripts/retrieve_"$clientName"_key\" <<copied_unlock.rsa>>" >> ~/.ssh/authorized_keys
```

### Adding cryptkeys to the cryptvm

These steps are executed on the **cryptvm**. Variables are used.

```bash
# Create and mount tmpfs (to not leave traces on any filesystem).
root@cryptvm:~$ mkdir tmp-mount && mount -t tmpfs none ./tmp-mount

# Retrieve keyfile
root@cryptvm:~$ ssh $keyHost -i /etc/initramfs-tools/root/.ssh/unlock_rsa -o UserKnownHostsFile=/etc/initramfs-tools/root/.ssh/known_hosts "$mac" > ./tmp-mount/keyfile
```
If the command above executed successfully, you can check the keyfile contents to make sure that the keyfile was transfered successfully. 

Proceed with adding the key to your crypto devices:
```bash
# Add key to crypto device. Make sure to adjust the device.
root@cryptvm:~$ cryptsetup luksAddKey /dev/sda5 ./tmp-mount/keyfile
```
After adding the key to the device, adjust /etc/crypttab to include the keyscript. It should look like this:
```bash
sda5_crypt UUID=<uuid> none luks,keyscript=/lib/cryptsetup/scripts/get_key_ssh
```

### Finalizing

These steps are executed on the **cryptvm**. Variables are used.

Please double check all steps above. If any of the steps failed or were not executed, you may encounter an unbootable system. If you double checked everything, proceed with building new initramfs and reboot.

```bash
root@cryptvm:~$ update-initramfs -u -k all
root@cryptvm:~$ reboot
```

Your cryptvm now should boot automatically into your fully encrypted system.

### Troubleshooting

#### Manual unlocking

If the keyserver should be unreachable for whatever reason, you will be dropped into the `(initramfs)`-shell after a few minutes. From here you will be able to unlock your encrypted partition manually using a password. For this to work it is critical, that *CRYPTSETUP=y* has been set, before creating the initramfs image or else the cryptsetup won't be available in initramfs emergency shell.

```bash
(initramfs) cryptsetup open /dev/sda5 sda5_crypt
Enter passphrase for /dev/sda5:
(initramfs) exit
```

Maybe you will need to modify `sda5` and `sda5_crypt` accordingly.

#### Issues on initial setup

If something went wrong on the initial setup and you're locked out, you can use the backed up initrd.img.cryptbootbackup. In order to do that, you would hit the *e*-key on the entry in GRUB. In this editor you'd edit the last line `initrd /initrd.img-4.9.0-7-amd64` line to say `initrd initrd.img.cryptbootbackup` and press F10. Since the backup will only be created by the script, this will probably not work if the setup should break later on, after new kernel versions have been installed.

## Contributing
Contributions and feature requests are always welcome!

If you have any additions, examples or bugfixes ready, feel free to create a pull request on GitHub. The pull requests will be reviewed and will be merged as soon as possible. To ease the process of merging the pull requests, please create one pull request per feature/fix, so those can be selectively included in the scripts.
