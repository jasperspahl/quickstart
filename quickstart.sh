#!/bin/sh
# Script to auto configure arch
# by Jasper Spahl <jasperspahl@web.de>

### OPTIONS AND VARIABLES ###

[ -z "$aurhelper" ] && aurhelper="yay"
[ -z "$progsfile"] && progsfile="https://raw.githubusercontent.com/jasperspahl/quickstart/main/progs.csv"

### FUNCTIONS ###

installpkg(){ pacman --noconfirm --needed -S "$1" >/dev/null 2>&1 ;}

error() { clear; printf "ERROR: \\n%s\\n" "$1" >&2; exit 1;}

getuser() { \
	# Prompts user for new username
	[ "$1" = "User exists" ] && \
	       	name=$(dialog --inputbox "The user \"$name\" already exists on this install. Please pick another username." 10 60 3>&1 1>&2 2>&3 3>&1) || \
		name=$(dialog --inputbox "First, please enter a name for the user account." 10 60 3>&1 1>&2 2>&3 3>&1) || return 1
	while ! echo "$name" | grep -q "^[a-z_][a-z0-9_-]*$"; do
		name=$(dialog --no-cancel --inputbox "Username not valid. Give a username beginning with a letter, with only lowercase letters, - or _." 10 60 3>&1 1>&2 2>&3 3>&1)
	done

	while { id -u $name >/dev/null 2>&1; }; do
		getuser "User exists"
	done ;}

getuserandpass() { \
	getuser || return 1
	pass1=$(dialog --no-cancel --passwordbox "Enter a password for \"$name\"" 10 60 3>&1 1>&2 2>&3 3>&1)
	pass2=$(dialog --no-cancel --passwordbox "Retype password" 10 60 3>&1 1>&2 2>&3 3>&1)
	while ! [ "$pass1" = "$pass2" ]; do
		unset pass2
		pass1=$(dialog --no-cancel --passwordbox "Passwords do not match.\\n\\n Enter password again." 10 60 3>&1 1>&2 2>&3 3>&1)
		pass2=$(dialog --no-cancel --passwordbox "Retype password" 10 60 3>&1 1>&2 2>&3 3>&1)
	done ;}

preinstallmsg() { \
	dialog --title "Let's get this party started" --yes-label "Let's go!" --no-label "No, nevermind!" --yesno "The rest of the installation will now be totally automated, so you can sit back and relax.\\n\\nIt will take some time, but when done, you can relax even more with your complete system\\n\\nNow just press <Let's go!> and the system will begin installation!" 13 60 || { clear; exit 1; }
	}

refreshkeys() { \
	dialog --infobox "Refreshing Arch Keyring ..." 4 50
	pacman --noconfirm -S archlinux-keyring > /dev/null 2>&1
	}

adduserandpass() { \
	#adds user `$name` with password $pass1.
	dialog --infobox "Adding user \"$name\" ..." 4 50
	useradd -m -g wheel -s /bin/zsh "$name" > /dev/null 2>&1 ||
	usermod -a -G wheel "$name" && mkdir -p /home/"$name" && chown "$name":wheel /home/"$name"
	repodir="/home/$name/.local/src"; mkdir -p "$repodir"; chown -R "$name":wheel "$(dirname "$repodir")"
	echo "$name:$pass1" | chpasswd
	unset pass1 pass2 ;}

newterms() { \
	sed -i "/#QUICKSTART/d/" /etc/sudoers
	echo "$* #QUICKSTART" >> /etc/sudoers ;}

manualinstall() { # Installs $1 manually if not installed. Used only for AUR helper here.
	[ -f "/usr/bin/$1" ] || (
	dialog --infobox "Installing \"$1\", an AUR helper..." 4 50
	cd /tmp || exit 1
	rm -rf /tmp/"$1"*
	curl -sO https://aur.archlinux.org/cgit/aur.git/snapshot/"$1".tar.gz &&
	sudo -u "$name" tar -xvf "$1".tar.gz >/dev/null 2>&1 &&
	cd "$1" &&
	sudo -u "$name" makepkg --noconfirm -si >/dev/null 2>&1
	cd /tmp | return 1) ;}

maininstall() { # Installs all needed programs form the main repo.
	dialog --title "QUICKSTART Installation" --infobox "Installing \`$1\` ($n of $total). $1 $2" 5 70
	installpkg "$1"
}

gitmakeinstall(){
	progname="$(basename "$1" .git)"
	dir="$repodir/$progname"
	dialog --title "QUICKSTART Installation" --infobox "Installing \`$progname\` ($n of $total) via \`git\` and \`make\`. $(basename $1) $2" 5 70
	sudo -u "$name" git clone --depth 1 "$1" "$dir" >/dev/null 2>&1 || { cd "$dir" || return 1 ; sudo -u "$name" git pull --force origin master;}
	make >/dev/null 2>&1
	make install >/dev/null 2>&1
	cd /tmp || return 1 ;}

aurinstall() {\
	dialog --title "QUICKSTART Installation" --infobox "Installing \`$1\` ($n of $total) from the AUR. $1 $2" 5 70
	echo "$aurinstalled" | grep -q "^$1$" && return 1
	sudo -u "$name" $aurhelper -S --noconfirm "$1" >/dev/null 2>&1
}

pipinstall() { \
	dialog --title "LARBS Installation" --infobox "Installing the Python package \`$1\` ($n of $total). $1 $2" 5 70
	[ -x "$(command -v "pip")" ] || installpkg python-pip >/dev/null 2>&1
	yes | pip install "$1"
	}

installationloop() { \
	([ -f "$progsfile" ] && cp "$progsfile" /tmp/progs.csv) || curl -Ls "$progsfile" | sed '/^#/d' > /tmp/progs.csv
	total=$(wc -l < /tmp/progs.csv)
	aurinstalled=$(pacman -Qqm)
	while IFS=, read -r tag program comment; do
		n=$((n+1))
		echo "$comment" | grep -q "^\".*\"$" && comment="$(echo "$comment" | sed "s/\(^\"\|\"$\)//g")"
		case "$tag" in
			"A") aurinstall "$program" "$comment" ;;
			"G") gitmakeinstall "$program" "$comment" ;;
			"P") pipinstall "$program" "$comment" ;;
			*) maininstall "$program" "$comment" ;;
		esac
	done < /tmp/progs.csv ;}
### The ACTUAL SCRIPT ###

### This is how everythin happens an intuitiva format and order.

# Check if user is root on Arch distro. Install dialog.
pacman --noconfirm --needed -Sy dialog || error "Are you sure you're running this as the root user, are on an Arch-based distribution and have an internet connection?"

# Get user and pick password
getuserandpass || error "User exited"

# Show Preinstall message
preinstallmsg || error "User exited"

# Refresh Arch keyrings.
refreshkeys || error "Error automaticlly refreshing Arch keyring. Consider doing so manully."

for x in curl base-devel git ntp zsh; do
	dialog --title "QUICKSTART Installation" --infobox "Installing \`$x\` which is required to install and configure other programs." 5 70
	installpkg "$x"
done

dialog --title "QUICKSTART Installation" --infobox "Synchornizing system time to ensure successful and secure installation of software ..." 4 70
ntpdata 0.us.pool.ntp.org > /dev/null 2>&1

adduserandpass || error "Error adding username and/or password."

[ -f /etc/sudoers.pacnew ] && cp /etc/sudoers.pacnew /etc/sudoers # Just in case

# Allow user to run sudo without a password. Since AUR programs must be installed
# in a fakeroot enviroment, this is required for all builds with AUR.
newperms "%wheel ALL=(ALL) NOPASSWD: ALL"

# Make pacman and yay colorful and adds eye candy on the progress bar because why not.
grep -q "^Color" /etc/pacman.conf || sed -i "s/^#Color$/Color/" /etc/pacman.conf
grep -q "ILoveCandy" /etc/pacman.conf || sed -i "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf

# use all cores for compilation.
sed -i "s/-j2/-j$(nproc)/;s/^#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf

manialinstall $aurhelper || error "Failed to install AUR helper."

# The command that does all the installing. Reads the progs.csv file and
# installs each needed program the way required. Be sure to run this only after user has been created and has privileges to run sudo without a password and all build dependencies are installed.
installationloop

# Make zsh the default shell for the user.
chsh -s /bin/zsh "$name" >/dev/null 2>&1
sudo -u "$name" mkdir -p "/home/$name/.cache/zsh/"
