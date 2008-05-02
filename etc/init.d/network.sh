#!/bin/sh
# /etc/init.d/network.sh - Network initialisation boot script.
# Config file is: /etc/network.conf
#
. /etc/init.d/rc.functions
. /etc/network.conf

# Set hostname.
echo -n "Setting hostname... "
/bin/hostname -F /etc/hostname
status

# Configure loopback interface.
echo -n "Configure loopback... "
/sbin/ifconfig lo 127.0.0.1 up
/sbin/route add 127.0.0.1 lo
status

# For a dynamic IP with DHCP.
if [ "$DHCP" = "yes" ] ; then
	echo "Starting udhcpc client on: $INTERFACE... "
	/sbin/udhcpc -b -i $INTERFACE -p /var/run/udhcpc.$INTERFACE.pid
fi

# For a static IP.
if [ "$STATIC" = "yes" ] ; then
	echo "Configuring static IP on $INTERFACE: $IP... "
	/sbin/ifconfig $INTERFACE $IP netmask $NETMASK up
	/sbin/route add default gateway $GATEWAY
	# Multi-DNS server in $DNS_SERVER.
	/bin/mv /etc/resolv.conf /tmp/resolv.conf.$$
	for NS in $DNS_SERVER
	do
		echo "nameserver $NS" >> /etc/resolv.conf
	done
fi

# For wifi (experimental).
if [ "$WIFI" = "yes" ] || grep -q "wifi" /proc/cmdline; then
	iwconfig $WIFI_INTERFACE essid $ESSID
	echo "Starting udhcpc client on: $INTERFACE... "
	/sbin/udhcpc -b -i $WIFI_INTERFACE \
		-p /var/run/udhcpc.$WIFI_INTERFACE.pid
fi
