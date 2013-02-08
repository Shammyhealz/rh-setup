# OpenVPN setup script
# Created by Shammyhealz
# Feel free to use as you see fit

echo 'What is the IP address for this server?'
read $oip

echo 'What port would you like to use? (Use 8000 if you don\'t know)'
read $oport

echo 'How many bits of encryption? (Use 1024 if you don\'t care)'
read $bits

echo 'What interface do you want to use?'
echo 'This is normally eth0 unless this is a VPN or server with multiple connections'
read $iface

aptitude install -y openvpn zip mutt

# Create the easy-rsa directory and copy over the files for ease of use.
cd /etc/openvpn
mkdir easy-rsa
cp -R /usr/share/doc/openvpn/examples/easy-rsa/2.0/* easy-rsa
chmod -R +x easy-rsa

cd easy-rsa

# Create the vars file, has to be done with echo to allow changing the bits on the encryption

echo '# easy-rsa parameter settings

# NOTE: If you installed from an RPM,
# dont edit this file in place in
# /usr/share/openvpn/easy-rsa --
# instead, you should copy the whole
# easy-rsa directory to another location
# (such as /etc/openvpn) so that your
# edits will not be wiped out by a future
# OpenVPN package upgrade.

# This variable should point to
# the top level of the easy-rsa
# tree.
export EASY_RSA="`pwd`"

#
# This variable should point to
# the requested executables
#
export OPENSSL="openssl"
export PKCS11TOOL="pkcs11-tool"
export GREP="grep"


# This variable should point to
# the openssl.cnf file included
# with easy-rsa.
export KEY_CONFIG=`$EASY_RSA/whichopensslcnf $EASY_RSA`

# Edit this variable to point to
# your soon-to-be-created key
# directory.
#
# WARNING: clean-all will do
# a rm -rf on this directory
# so make sure you define
# it correctly!
export KEY_DIR="$EASY_RSA/keys"

# Issue rm -rf warning
echo NOTE: If you run ./clean-all, I will be doing a rm -rf on $KEY_DIR

# PKCS11 fixes
export PKCS11_MODULE_PATH="dummy"
export PKCS11_PIN="dummy"

# Increase this to 2048 if you
# are paranoid.  This will slow
# down TLS negotiation performance
# as well as the one-time DH parms
# generation process.
export KEY_SIZE='$bits'

# In how many days should the root CA key expire?
export CA_EXPIRE=3650

# In how many days should certificates expire?
export KEY_EXPIRE=3650

# These are the default values for fields
# which will be placed in the certificate.
# Dont leave any of these fields blank.
export KEY_COUNTRY="US"
export KEY_PROVINCE="CA"
export KEY_CITY="SanFrancisco"
export KEY_ORG="Fort-Funston"
export KEY_EMAIL="me@myhost.mydomain"' > vars

# Standard setup, loads the variables

./vars
source ./vars

# Removes old certs

./clean-all

# Creates server static keys

./build-ca

./build-key-server server

./build-dh


# Creates server config file with user options

echo 'port '$oport'
proto udp
dev tun

ca      /etc/openvpn/easy-rsa/keys/ca.crt    # generated keys
cert    /etc/openvpn/easy-rsa/keys/server.crt
key     /etc/openvpn/easy-rsa/keys/server.key  # keep secret
dh      /etc/openvpn/easy-rsa/keys/dh'$bits'.pem

server 10.9.8.0 255.255.255.0  # internal tun0 connection IP
ifconfig-pool-persist ipp.txt

push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"

keepalive 10 120

comp-lzo         # Compression - must be turned on at both end
persist-key
persist-tun

push "redirect-gateway def1"

verb 3  # verbose mode
client-to-client' > /etc/openvpn/server.conf

# Create required directories for logging

mkdir /etc/openvpn/log
touch /etc/openvpn/log/openvpn-status.log

# Restart OpenVPN to load new settings

/etc/init.d/openvpn restart

# Enable forwarding

echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf

# Iptables rules to forward the connections

iptables -A FORWARD -i $iface -o tun0 -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -s 10.9.8.0/24 -o $iface -j ACCEPT
iptables -t nat -A POSTROUTING -s 10.9.8.0/24 -o $iface -j MASQUERADE

iptables-save > /etc/iptables.up.rules

echo '#!/bin/bash
 /sbin/iptables-restore < /etc/iptables.up.rules' > /etc/network/if-pre-up.d/iptables
chmod +x /etc/network/if-pre-up.d/iptables

# Allow users to create more certificates if they need to

response="y"

# Generic loop based on string value

while [ "$response" = "y" ]
do
	echo 'Name to use for certificate? (Blackhat, phone, etc)'
	read client
	
	echo 'What is the email you would like to send these certs to?'
	read openvpnemail
	
	./build-key $client

	cd keys

	echo 'client
	dev tun
	port '$oport'
	proto udp

	remote '$oip' '$oport'            # VPN server IP : PORT
	nobind
	
	resolv-retry infinite
	ca ca.crt
	cert '$client'.crt
	key '$client'.key

	comp-lzo
	persist-key
	persist-tun
	route-method exe
	verb 3' > $client.ovpn

	mkdir openvpn

	cp $client* openvpn
	
	cp ca.crt openvpn

	zip -r $client.zip openvpn

	mv $client.zip /home
	
	rm -r openvpn

	echo 'All of the files for this user including a Windows config have been stored in /home/'$client'.zip extract the contents of this zip archive to use.'

	cd ..

	echo 'Do you need to generate more certificates? y or n'
	read response
done