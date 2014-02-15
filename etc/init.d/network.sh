#!/bin/sh
#
# /etc/init.d/network.sh : Network initialization boot script
# Configuration file     : /etc/network.conf
#
. /etc/init.d/rc.functions

if [ -z "$2" ]; then
	. /etc/network.conf
else
	. $2
fi

boot() {
	# Set hostname.
	echo -n "Setting hostname to: $(cat /etc/hostname)"
	/bin/hostname -F /etc/hostname
	status

	# Configure loopback interface.
	echo -n "Configuring loopback..."
	/sbin/ifconfig lo 127.0.0.1 up
	/sbin/route add -net 127.0.0.0 netmask 255.0.0.0 dev lo
	status

	[ -s /etc/sysctl.conf ] && sysctl -p /etc/sysctl.conf
}

# Use ethernet
eth() {
	ifconfig $INTERFACE up
}

# For wifi. Users just have to enable it through yes and usually
# essid any will work and the interface is autodetected.
wifi() {
	if [ "$WIFI" = "yes" ] || fgrep -q "wifi" /proc/cmdline; then
		ifconfig $INTERFACE down

		# Confirm if $WIFI_INTERFACE is the wifi interface
		if [ ! -d /sys/class/net/$WIFI_INTERFACE/wireless ]; then
			echo "$WIFI_INTERFACE is not a wifi interface, changing it."
			WIFI_INTERFACE=$(fgrep : /proc/net/dev | cut -d: -f1 | \
				while read dev; do iwconfig $dev 2>&1 | \
					fgrep -iq "essid" && { echo $dev ; break; }; \
				done)
			[ -n "$WIFI_INTERFACE" ] && sed -i \
				"s/^WIFI_INTERFACE=.*/WIFI_INTERFACE=\"$WIFI_INTERFACE\"/" \
				/etc/network.conf
		fi

		echo -n "Configuring $WIFI_INTERFACE..."
		ifconfig $WIFI_INTERFACE up 2>/dev/null
		if iwconfig $WIFI_INTERFACE | fgrep -q "Tx-Power"; then
			iwconfig $WIFI_INTERFACE txpower on
		fi
		status

		IWCONFIG_ARGS=""
		[ -n "$WPA_DRIVER" ] || WPA_DRIVER="wext"
		[ -n "$WIFI_MODE" ] && IWCONFIG_ARGS="$IWCONFIG_ARGS mode $WIFI_MODE"
		[ -n "$WIFI_CHANNEL" ] && IWCONFIG_ARGS="$IWCONFIG_ARGS channel $WIFI_CHANNEL"
		[ -n "$WIFI_AP" ] && IWCONFIG_ARGS="$IWCONFIG_ARGS ap $WIFI_AP"
		
		# Unencrypted network
		if [ "$WIFI_KEY" == "" -o "$WIFI_KEY_TYPE" == "" ]; then
			iwconfig $WIFI_INTERFACE essid "$WIFI_ESSID" $IWCONFIG_ARGS
		fi
		
		# Encrypted network
		[ -n "$WIFI_KEY" ] && case "$WIFI_KEY_TYPE" in
			wep|WEP)
				# wpa_supplicant can also deal with wep encryption
				# Tip: Use unquoted strings for hexadecimal key in wep_key0
				echo "Creating: /etc/wpa/wpa.conf"
				cat /etc/wpa/wpa_empty.conf > /etc/wpa/wpa.conf
				cat >> /etc/wpa/wpa.conf << EOT
network={
	ssid="$WIFI_ESSID"
	scan_ssid=1
	key_mgmt=NONE
	wep_key0=$WIFI_KEY
	wep_tx_keyidx=0
	priority=5
}
EOT
				echo "Starting wpa_supplicant for NONE/WEP..."
				wpa_supplicant -B -W -c/etc/wpa/wpa.conf -D$WPA_DRIVER \
					-i$WIFI_INTERFACE ;;
			
			wpa|WPA)
				# load pre-configured multiple profiles
				echo "Creating: /etc/wpa/wpa.conf"
				cat /etc/wpa/wpa_empty.conf > /etc/wpa/wpa.conf
				if [ "$WIFI_IDENTITY" ]; then
					cat >> /etc/wpa/wpa.conf << EOT
network={
	ssid="$WIFI_ESSID"
	key_mgmt=WPA-EAP
	scan_ssid=1
	identity="$WIFI_IDENTITY"
	password="$WIFI_PASSWORD"
}
EOT
				else
					cat >> /etc/wpa/wpa.conf << EOT
network={
	ssid="$WIFI_ESSID"
	scan_ssid=1
	proto=WPA RSN
	key_mgmt=WPA-PSK WPA-EAP
	psk="$WIFI_KEY"
	priority=5
}
EOT
				fi
				echo "Starting wpa_supplicant for WPA-PSK..."
				wpa_supplicant -B -W -c/etc/wpa/wpa.conf \
					-D$WPA_DRIVER -i$WIFI_INTERFACE ;;
			
			any|ANY)
				echo "Creating: /etc/wpa/wpa.conf"
				cat /etc/wpa/wpa_empty.conf > /etc/wpa/wpa.conf
				cat >> /etc/wpa/wpa.conf << EOT
network={
	ssid="$WIFI_ESSID"
	scan_ssid=1
	key_mgmt=WPA-EAP WPA-PSK IEEE8021X NONE
	group=CCMP TKIP WEP104 WEP40
	pairwise=CCMP TKIP
	psk="$WIFI_KEY"
	priority=5
}
EOT
				echo "Starting wpa_supplicant for any key type..."
				wpa_supplicant -B -W -c/etc/wpa/wpa.conf \
					-D$WPA_DRIVER -i$WIFI_INTERFACE ;;
		esac
		INTERFACE=$WIFI_INTERFACE
	fi
}

# WPA DHCP script
wpa() {
	wpa_cli -a"/etc/init.d/wpa_action.sh" -B
}

# For a dynamic IP with DHCP.
dhcp() {
	if [ "$DHCP" = "yes" ]  ; then
		echo "Starting udhcpc client on: $INTERFACE..."
		# Is wpa wireless && wpa_ctrl_open interface up ?
		if [ -d /var/run/wpa_supplicant ] && [ "$WIFI" = "yes" ]; then
			wpa
		else # fallback on udhcpc: wep, eth
			/sbin/udhcpc -b -T 1 -A 12 -i $INTERFACE -p \
			/var/run/udhcpc.$INTERFACE.pid
		fi
	fi
}

# For a static IP.
static_ip() {
	if [ "$STATIC" = "yes" ] ; then
		echo "Configuring static IP on $INTERFACE: $IP..."
		if [ -n "$BROADCAST" ]; then
			/sbin/ifconfig $INTERFACE $IP netmask $NETMASK broadcast $BROADCAST up
		else
			/sbin/ifconfig $INTERFACE $IP netmask $NETMASK up
		fi
		
		# Use ip to set gateways if iproute.conf exists
		if [ -f /etc/iproute.conf ]; then
		    while read line
			do
				ip route add $line
			done < /etc/iproute.conf
		else
			/sbin/route add default gateway $GATEWAY
		fi
		
		# wpa_supplicant waits for wpa_cli
		[ -d /var/run/wpa_supplicant ] && wpa_cli -B
		
		# Multi-DNS server in $DNS_SERVER.
		/bin/mv /etc/resolv.conf /tmp/resolv.conf.$$
		for NS in $DNS_SERVER
		do
			echo "nameserver $NS" >> /etc/resolv.conf
		done
		if [ ! -z $DOMAIN ];then
		    echo "search $DOMAIN" >> /etc/resolv.conf
		fi
		for HELPER in /etc/ipup.d/*; do
			[ -x $HELPER ] && $HELPER $INTERFACE $DNS_SERVER
		done
	fi
}

# stopping everything
stop() {
	echo "stopping all interfaces"
	ifconfig $INTERFACE down
	ifconfig $WIFI_INTERFACE down

	echo "Killing all daemons"
	killall udhcpc
	killall wpa_supplicant 2>/dev/null

	if iwconfig $WIFI_INTERFACE | fgrep -q "Tx-Power"; then
		echo "Shutting down wifi card"
		iwconfig $WIFI_INTERFACE txpower off
	fi
}

start() {
	eth
	wifi
	dhcp
	static_ip
	# change default lxpanel panel iface
	if [ -f /etc/lxpanel/default/panels/panel ]; then
		sed -i "s/iface=.*/iface=$INTERFACE/" \
			/etc/lxpanel/default/panels/panel
	fi
}

# looking for arguments:
if [ -z "$1" ]; then
	boot
	start
else
	case $1 in
		start)
			start ;;
		stop)
			stop ;;
		restart)
			stop
			start ;;
		*)
			echo ""
			echo -e "\033[1mUsage:\033[0m /etc/init.d/`basename $0` [start|stop|restart]"
			echo ""
			echo -e "	Default configuration file is \033[1m/etc/network.conf\033[0m"
			echo -e "	You can specify another configuration file in the second argument:"
			echo -e "	\033[1mUsage:\033[0m /etc/init.d/`basename $0` [start|stop|restart] file.conf"
			echo "" ;;
	esac
fi
