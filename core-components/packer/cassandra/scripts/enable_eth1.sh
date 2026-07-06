#!/bin/bash

# Bring the newly-attached secondary ENI into use, and report its (static)
# IP. Two generations of behavior:
#
#   - Amazon Linux 2 / RHEL 7: no automatic multi-ENI handling. We manually
#     create an ifcfg-eth1, ifup it, and ifdown eth0 -- the ENI always comes
#     up as "eth1" under classic udev persistent-net naming.
#
#   - Amazon Linux 2023+ (amazon-ec2-net-utils): udev + ec2-net-utils
#     automatically bring up any attached ENI (predictable ensN naming) with
#     its own DHCP lease AND its own source-based routing table (`ip rule`),
#     so traffic sourced from that ENI's IP already egresses correctly with
#     no asymmetric-routing problem. No ifup/ifdown/interface toggling is
#     needed or possible (ifup/ifdown don't exist here) -- we only need to
#     find which interface the ENI landed on.

if [[ -x /sbin/ifup ]]; then
  # legacy path (Amazon Linux 2 / RHEL 7)
  cd /etc/sysconfig/network-scripts

  if [[ ! -e ifcfg-eth1 ]]; then
    cp ifcfg-eth0 ifcfg-eth1
    cp ifcfg-eth0 ifcfg-eth0.bak
    sed -i 's/eth0/eth1/g' ifcfg-eth1
    sed -i 's/ONBOOT=yes/ONBOOT=no/g' ifcfg-eth0
  fi

  # make sure eth1 is UP
  if [[ $(ip link show | grep -c "eth1.*state UP") == 0 ]]; then
    /sbin/ifup eth1
    sleep 10
  fi

  # make sure eth0 is DOWN
  if [[ $(ip link show | grep -c "eth0.*state DOWN") == 0 ]]; then
    echo "FYI: if running this manually while SSHing on eth0, your session is about to hang..." >&2
    /sbin/ifdown eth0
    sleep 3
  fi

  eni_iface=eth1
else
  # modern path (Amazon Linux 2023+, amazon-ec2-net-utils): udev already
  # brings the new ENI up with its own IP and routing table on attach --
  # just wait for it and find which local interface it landed on.
  imds_token=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
  primary_mac=$(curl -s -H "X-aws-ec2-metadata-token: ${imds_token}" http://169.254.169.254/latest/meta-data/mac)

  eni_mac=""
  for i in $(seq 1 30); do
    for mac in $(curl -s -H "X-aws-ec2-metadata-token: ${imds_token}" http://169.254.169.254/latest/meta-data/network/interfaces/macs/); do
      mac="${mac%/}"
      if [[ "${mac}" != "${primary_mac}" ]]; then
        eni_mac="${mac}"
        break 2
      fi
    done
    sleep 2
  done

  if [[ -z "${eni_mac}" ]]; then
    echo "ERROR: no secondary ENI found in instance metadata" >&2
    exit 1
  fi

  eni_iface=""
  for i in $(seq 1 30); do
    eni_iface=$(ip -o link show | awk -v mac="${eni_mac}" 'tolower($0) ~ tolower(mac) {print $2}' | cut -d: -f1 | head -1)
    [[ -n "${eni_iface}" ]] && break
    sleep 2
  done

  if [[ -z "${eni_iface}" ]]; then
    echo "ERROR: no local interface found for MAC ${eni_mac}" >&2
    exit 1
  fi

  # wait for udev/ec2-net-utils to finish assigning it a DHCP address
  for i in $(seq 1 30); do
    ip -4 -o addr show "${eni_iface}" | grep -q inet && break
    sleep 2
  done
fi

# capture current IP (use `ip`, not `ifconfig` -- net-tools isn't guaranteed
# present on newer images)
my_eni_ip=$(ip -4 -o addr show "${eni_iface}" | awk '{print $4}' | cut -d/ -f1 | tr '.' '-')
my_eni_hostname=ip-${my_eni_ip}.compute.internal
ip_addr=$(ip -4 -o addr show "${eni_iface}" | awk '{print $4}' | cut -d/ -f1)

# make sure hostname is set properly in /etc/hosts
if [[ ! $(hostname -i) =~ "${ip_addr}" ]]; then
  hostnamectl set-hostname ${my_eni_hostname}
  echo "${ip_addr} ${my_eni_hostname} ip-${my_eni_ip}" >> /etc/hosts
  echo "preserve_hostname: true" >> /etc/cloud/cloud.cfg
fi

# report the ENI's IP on stdout -- the caller (bootstrap.sh) no longer knows
# the interface name in advance (eth1 on legacy AMIs, ensN on AL2023+)
echo "${ip_addr}"
