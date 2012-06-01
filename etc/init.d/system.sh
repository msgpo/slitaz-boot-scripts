#!/bin/sh
#
# /etc/init.d/system.sh : SliTaz hardware configuration
#
# This script configures the sound card and screen. Tazhw is used earlier
# at boot time to autoconfigure PCI and USB devices. It also configures
# system language, keyboard and TZ in live mode and start X.
#
. /etc/init.d/rc.functions
. /etc/rcS.conf

# Parse cmdline args for boot options (See also rcS and bootopts.sh).
XARG=""
for opt in $(cat /proc/cmdline)
do
	case $opt in
		console=*)
			sed -i "s/tty1/${opt#console=}/g;/^tty[2-9]::/d" \
				/etc/inittab ;;
		sound=*)
			DRIVER=${opt#sound=} ;;
		xarg=*)
			XARG="$XARG ${opt#xarg=}" ;;
		screen=*)
			SCREEN=${opt#screen=} ;;
		*)
			continue ;;
	esac
done

# Sound configuration stuff. First check if sound=no and remove all
# sound Kernel modules.
if [ -n "$DRIVER" ]; then
	case "$DRIVER" in
		no)
			echo -n "Removing all sound kernel modules..."
			rm -rf /lib/modules/$(uname -r)/kernel/sound
			status
			echo -n "Removing all sound packages..."
			for i in $(grep -l '^DEPENDS=.*alsa-lib' /var/lib/tazpkg/installed/*/receipt) ; do
				pkg=${i#/var/lib/tazpkg/installed/}
				echo 'y' | tazpkg remove ${pkg%/*} > /dev/null
			done
			for i in alsa-lib mhwaveedit asunder libcddb ; do
				echo 'y' | tazpkg remove $i > /dev/null
			done
			status ;;
		noconf)
			echo "Sound configuration was disabled from cmdline..." ;;
		*)
			if [ -x /usr/sbin/soundconf ]; then
				echo "Using sound kernel module $DRIVER..."
				/usr/sbin/soundconf -M $DRIVER
			fi ;;
	esac
# Sound card may already be detected by PCI-detect.
elif [ -d /proc/asound ]; then
	# Restore sound config for installed system.
	if [ -s /var/lib/alsa/asound.state ]; then
		echo -n "Restoring last alsa configuration..."
		alsactl restore
		status
	else
		/usr/sbin/setmixer
	fi
	# Start soundconf to config driver and load module for Live mode
	# if not yet detected.
	/usr/bin/amixer >/dev/null || /usr/sbin/soundconf
else
	echo "Unable to configure sound card."
fi

# Locale config.
echo "Checking if /etc/locale.conf exists... "
if [ ! -s "/etc/locale.conf" ]; then
	echo "Setting system locale to: POSIX (English)"
	echo -e "LANG=POSIX\nLC_ALL=POSIX" > /etc/locale.conf
fi
. /etc/locale.conf
echo -n "Locale configuration: $LANG"
export LC_ALL
. /lib/libtaz.sh && status

# Keymap config. Default to us in live mode if kmap= was not used.
if [ ! -s "/etc/keymap.conf" ]; then
	echo "us" > /etc/keymap.conf
fi
kmap=$(cat /etc/keymap.conf)
echo "Keymap configuration: $kmap"
/sbin/tazkeymap $kmap

# Timezone config. Set timezone using the keymap config for fr, be, fr_CH
# and ca with Montreal.
if [ ! -s "/etc/TZ" ]; then
	case "$kmap" in
		fr-latin1|be-latin1)
			echo "Europe/Paris" > /etc/TZ ;;
		fr_CH-latin1|de_CH-latin1)
			echo "Europe/Zurich" > /etc/TZ ;;
		cf) echo "America/Montreal" > /etc/TZ ;;
		*) echo "UTC" > /etc/TZ ;;
	esac
fi

# Activate an eventual swap file or partition
if [ "$(fdisk -l | grep swap)" ]; then
	for swd in $(fdisk -l | sed '/swap/!d;s/ .*//'); do
		if ! grep -q "$swd	" /etc/fstab; then
			echo "Swap memory detected on: $swd"
		cat >> /etc/fstab <<EOT
$swd	swap	swap	default	0 0
EOT
		fi
	done
fi
if grep -q swap /etc/fstab; then
	echo -n "Activating swap memory..."
	swapon -a && status
fi

# Xorg auto configuration: $HOME is not yet set. We config even if
# screen=text so X can be started by users via 'startx'
if [ ! -s /etc/X11/xorg.conf ] && [ -x /usr/bin/Xorg ]; then
	echo "Configuring Xorg..."
	HOME=/root
	tazx config-xorg 2>/var/log/xorg.configure.log
fi

# Start X sesssion as soon as possible
if [ "$SCREEN" != "text" ] && [ "$LOGIN_MANAGER" ]; then
	echo -n "Starting X environment..."
	/etc/init.d/dbus start >/dev/null
	/etc/init.d/$LOGIN_MANAGER start >/dev/null &
	status
fi

# Start TazPanel
[ -x /usr/bin/tazpanel ] && tazpanel start
