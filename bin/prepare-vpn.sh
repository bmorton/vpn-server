#!/bin/bash

[ "$DEBUG" == "1" ] && set -x

set -e

if [ ! -d $VPN_PATH/easy-rsa/keys ]; then
   # Copy easy-rsa tools to /etc/openvpn
   rsync -avz /usr/share/easy-rsa $VPN_PATH/

   # Configure easy-rsa vars file
   perl -p -i -e "s/export KEY_COUNTRY=.*/export KEY_COUNTRY=\"CA\"/g" $VPN_PATH/easy-rsa/vars
   perl -p -i -e "s/export KEY_PROVINCE=.*/export KEY_PROVINCE=\"BARCELONA\"/g" $VPN_PATH/easy-rsa/vars
   perl -p -i -e "s/export KEY_CITY=.*/export KEY_CITY=\"CASTELLDEFELS\"/g" $VPN_PATH/easy-rsa/vars
   perl -p -i -e "s/export KEY_ORG=.*/export KEY_ORG=\"NIXEL\"/g" $VPN_PATH/easy-rsa/vars
   perl -p -i -e "s/export KEY_EMAIL=.*/export KEY_EMAIL=\"manel\@nixelsolutions.com\"/g" $VPN_PATH/easy-rsa/vars
   perl -p -i -e "s/export KEY_OU=.*/export KEY_OU=\"NIXEL\"/g" $VPN_PATH/easy-rsa/vars

   pushd $VPN_PATH/easy-rsa
   . ./vars
   ./clean-all
   ./build-ca --batch
   ./build-key-server --batch server
   ./build-dh
   ./build-key --batch docker_cloud_vpn_client
   openvpn --genkey --secret keys/ta.key
   popd
fi

# Update openvpn route
TUTUM_NETWORK_CIDR=`ip addr show dev ethwe | grep "inet " | awk '{print $2}' | xargs -i ipcalc -n {} | grep Network | awk '{print $2}' | awk -F/ '{print $1}'`
TUTUM_NETWORK_MASK=`ip addr show dev ethwe | grep "inet " | awk '{print $2}' | xargs -i ipcalc -n {} | grep Netmask | awk '{print $2}'`

# Create OpenVPN server config
cat > $VPN_PATH/server.conf <<EOF
port 1194
proto tcp
dev tun
keepalive 10 120
comp-lzo

user nobody
group nogroup

log-append /var/log/openvpn.log
verb 3

persist-key
persist-tun

ca easy-rsa/keys/ca.crt
cert easy-rsa/keys/server.crt
key easy-rsa/keys/server.key
dh easy-rsa/keys/dh2048.pem
tls-auth easy-rsa/keys/ta.key 0

server 10.8.0.0 255.255.255.0

push "route $TUTUM_NETWORK_CIDR $TUTUM_NETWORK_MASK"
EOF

# Enable tcp forwarding and add iptables MASQUERADE rule
iptables -t nat -F
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -j MASQUERADE
