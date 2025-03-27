#!/bin/bash

############ COLOURED BASH TEXT

# ANSI color codes
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

###############################

# Location
APPLICATION="network"
BASE="$HOME/bash.$APPLICATION"
FILES="$BASE/files"
SCRIPTS="$FILES/scripts"
APP_LIST="$FILES/packages.txt"    # File containing package names
# Pre-Configuration
BASH="$HOME/order_66"
# Log file for package installations
logFile="$HOME/network_install_log.txt"
# Define User
currentUser=$(whoami)


########################################################################## NAME SAMBA GROUP HERE
############ NAME SAMBA GROUP HERE

sambaShare="localShare" # Replace 'qShare' with your desired group name


########################################################################## NAME SHARE FOLDERS HERE
############ NAME SHARE FOLDERS HERE

# This is the names of the FOLDERs that will be created in L
S="shared"        # Change 'qSHARED' into what you want the folder be named.
N="nfs-share"     # Change 'qNFS_SHARE' into what you want the folder be named.


########################################################################## LOCATION
############ LOCATION

# This is a folder in your HOME directory, Rename or keep it as is.
# S, P & N will be folders that are located in this folder.
L="Network"
sha="shared"


########################################################################## REFERENCES
############ REFERENCES

# DO NOT CHANGE THESE! 
sCUT="/home/$currentUser"
sharedDir="$sCUT/$L/$sha/$S"
publicDir="$sCUT/$L/$sha/$P"
nfsExportDir="$sCUT/$L/$sha/$N"


########################################################################## FOLDER CREATION
############ FOLDER CREATION

# DO NOT CHANGE THESE!
sudo mkdir -p "$sCUT/$L"
sudo mkdir -p "$sCUT/$L/$sha"
sudo mkdir -p "$sCUT/$L/$sha/$S"
sudo mkdir -p "$sCUT/$L/$sha/$P"
sudo mkdir -p "$sCUT/$L/$sha/$N"

########################################################################## CODE STARTS
############ CODE STARTS

# Setting Computer Hostname
# Check current hostname
currentHostname=$(hostname)
echo -e "Current hostname: ${PURPLE}$currentHostname${NC}"

# Prompt user if they want to change the hostname
read -p "$(echo -e "${GREEN}Do you want to change the hostname?${NC} (y/n): ")" changeHostname

if [[ $changeHostname =~ ^[Yy]$ ]]; then
    # Prompt user for new hostname input
    read -p "$(echo -e "${GREEN}Enter the new hostname:${NC} ")" myRig

    # Update the hostname file
    echo "$myRig" | sudo tee /etc/hostname > /dev/null

    # Update /etc/hosts
    sudo sed -i "s/127.0.0.1.*/127.0.0.1 localhost $myRig/" /etc/hosts

    # Apply the hostname change
    sudo hostnamectl set-hostname "$myRig"

    # Notify user of completion
    echo -e "${GREEN}Hostname set to $myRig.${NC} Please restart your system to apply the changes."
else
    echo "Hostname remains as $currentHostname. No changes made."
fi

packages_txt() {
    # Check if $HOME/bash directory exists, if not create it
    if [ ! -d "$BASH" ]; then
        mkdir -p "$BASH"
        print_message "$GREEN" "Created directory: $BASH"
    fi
    
    # Check if $HOME/bash.pkmgr exists, delete it if it does
    if [ -d "$HOME/bash.pkmgr" ]; then
        print_message "$YELLOW" "Removing existing $HOME/bash.pkmgr"
        rm -rf "$HOME/bash.pkmgr"
    fi
    
    # Copy ../files/packages.txt to /home/user/bash
    cp "$APP_LIST" "$BASH"
    print_message "$CYAN" "Copied $APP_LIST to $BASH"
    
    # Get the Package Manager & Package Installer
    git clone https://github.com/Querzion/bash.pkmgr.git "$HOME/bash.pkmgr"
    chmod +x -R "$HOME/bash.pkmgr"
    sh "$HOME/bash.pkmgr/installer.sh"
    
    print_message "$GREEN" "Applications installed successfully."
}

# Function to create a directory if it doesn't exist
create_dir_if_not_exists() {
    local dir=$1
    if [ ! -d "$dir" ]; then
        sudo mkdir -p "$dir" && echo -e "${GREEN}Directory '$dir' created successfully.${NC}" || {
            echo -e "${RED}Error creating directory '$dir'.${NC}"
            exit 1
        }
    else
        echo -e "${YELLOW}Directory '$dir' already exists.${NC}"
    fi
}

# Install packages from ..bash/packages.txt
packages_txt

# Add user to groups, just because.
sudo usermod -aG storage,network,ftp $currentUser

# Backup the original smb.conf file
sudo cp -n /etc/samba/smb.conf{,.bak} || true
SMB="/etc/samba/smb.conf"

echo -e "${GREEN} Creating smb.conf file.${NC}"

# Write the content to the smb.conf file
sudo tee "$SMB" > /dev/null <<EOL
[global]
   workgroup = WORKGROUP
   server string = Samba Server
   netbios name = $currentHostname
   security = user
   map to guest = Bad User
   dns proxy = no
   server role = standalone server
   log file = /var/log/samba/%m.log
   max log size = 50

[Public]
   path = $publicDir
   browsable = yes
   writable = yes
   guest ok = yes
   read only = no
   public = yes

[$sambaShare]
   path = $sharedDir
   browseable = yes
   guest ok = yes
   public = yes
   writable = yes
   read only = no
EOL

testparm

echo -e "${GREEN} smb.conf file created at $SMB ${NC}"

# Pause the script
echo -e "${GREEN} PRESS ENTER TO CONTINUE. ${NC}"
read

# Create shared directories and set permissions
echo -e "${YELLOW} Creating shared directories and setting permissions... ${NC}"
create_dir_if_not_exists "$publicDir"
sudo chown -R "$currentUser:$sambaShare" "$publicDir"
sudo chmod -R 0775 "$publicDir"

create_dir_if_not_exists "$sharedDir"
sudo chown -R "$currentUser:$sambaShare" "$sharedDir"
sudo chmod -R 0775 "$sharedDir"

# Enable & start Samba and Avahi services
echo -e "${YELLOW} Enabling and starting Samba and Avahi services.${NC}"
sudo systemctl enable --now smb nmb avahi-daemon

# Configure nss-mdns
echo -e "${YELLOW} Configuring nss-mdns... ${NC}"
sudo sed -i 's/hosts: files mymachines myhostname/hosts: files mymachines myhostname mdns_minimal [NOTFOUND=return] dns/g' /etc/nsswitch.conf

# Install and configure NFS
echo -e "${YELLOW} Configuring NFS... ${NC}"

# Configure NFS exports
sudo tee -a /etc/exports > /dev/null <<EOL
$nfsExportDir 10.0.1.0/23(rw,sync,no_subtree_check)
EOL

sudo exportfs -ra  # Reload NFS exports
sudo systemctl enable --now nfs-server  # Restart NFS server

echo -e "${GREEN} NFS export configuration added and NFS server started.${NC}"

# Configure firewall (UFW)
echo -e "${YELLOW} Configuring UFW (Uncomplicated Firewall)... ${NC}"

# SMB ports
sudo ufw allow proto tcp from any to any port 139,445   # SMB/CIFS - File Sharing
sudo ufw allow proto udp from any to any port 137,138,5353   # SMB/CIFS - NetBIOS over TCP/UDP and Bonjour Service Discovery

# NFS ports
sudo ufw allow proto tcp from any to any port 2049   # NFS - TCP
sudo ufw allow proto udp from any to any port 2049   # NFS - UDP
sudo ufw allow proto tcp from any to any port 111    # NFS - TCP
sudo ufw allow proto udp from any to any port 111    # NFS - UDP

sudo ufw --force enable

# Restarting services
echo -e "${YELLOW} Restarting services... ${NC}"
sudo systemctl restart smb nmb avahi-daemon nfs-server

# Pause the script
echo -e "${GREEN} PRESS ENTER TO CONTINUE. ${NC}"
read

# Print status of services
echo -e "${YELLOW} Checking status of Samba, Avahi, NFS & UFW.${NC}"
sudo systemctl status smb nmb avahi-daemon nfs-server

echo -e "${RED} If the status is not enabled and active, reboot and test it again.${NC}"
echo -e "${GREEN} Setup completed! ${NC} You can now access the shared folder at ${CYAN}\\\\$currentHostname\\Public${NC}"

echo -e "${YELLOW} Installation log saved to: $logFile${NC}"
