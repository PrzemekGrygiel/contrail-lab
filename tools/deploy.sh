#!/bin/bash
# Author: bkupidura@juniper.net
#
#
# Simple script to deploy workshop labs
#
#
# Usage:
# BOOTSTRAP=1 CONTRAIL_VERSION=ocata-master-60 KOLLA_COMMIT=2145c8753fe55bc380498ac606a9f944cf9db36d ./deploy.sh 10.10.16.124
# BOOTSTRAP=1 INSTALL_CONTRAIL=1 CONTRAIL_VERSION=ocata-master-60 KOLLA_COMMIT=2145c8753fe55bc380498ac606a9f944cf9db36d ./deploy.sh 10.10.16.104
#
#
# ANSIBLE_DEPLOYER_URL - Ansible deployer URL
# ANSIBLE_DEPLOYER_COMMIT - Ansible deployer commit ID
# ANSIBLE_DEPLOYER_CLEANUP - Remove old contrail-ansible-deployer dir
# CONTRAIL_VERSION - Contrail version
# CONTRAIL_REGISTRY - Contrail registry
# KOLLA_COMMIT - Kolla commit ID
# NUMBER_OF_VMS - Number of VMS to spawn
# SERVER_HOST - KVM node IP
# REQUIRED_PACKAGES - Packages which should be install on KVM node
# NETWORK_PREFIX - KVM subnet prefix
# VMS_LAST_OCTET_PREFIX - Last octet IP for KVM
# BOOTSTRAP - Bootstrap environment (spawn KVM VMs, configure KVM VMs, install openstack)
# INSTALL_CONTRAIL - Install contrail
#
ANSIBLE_DEPLOYER_URL=https://github.com/Juniper/contrail-ansible-deployer
ANSIBLE_DEPLOYER_COMMIT=${ANSIBLE_DEPLOYER_COMMIT:-"master"}
ANSIBLE_DEPLOYER_CLEANUP=${ANSIBLE_DEPLOYER_CLEANUP:-0}
CONTRAIL_VERSION=${CONTRAIL_VERSION:-"latest"}
CONTRAIL_REGISTRY=${CONTRAIL_REGISTRY:-"opencontrailnightly"}
KOLLA_COMMIT=${KOLLA_COMMIT:-"2c011bf40afc783acf2f1765584c0cf4d4494a93"}
NUMBER_OF_VMS=${NUMBER_OF_VMS:-"3"}
SERVER_HOST=${SERVER_HOST:-$1}
REQUIRED_PACKAGES=${REQUIRED_PACKAGES:-"python-urllib3 libguestfs-tools libvirt-python virt-install libvirt git ansible-2.4.2.0 python-pip vim screen tcpdump ntp"}
NETWORK_PREFIX=${NETWORK_PREFIX:-"192.168.122"}
VMS_LAST_OCTET_PREFIX=${VMS_LAST_OCTET_PREFIX:-"10"}
BOOTSTRAP=${BOOTSTRAP:-0}
INSTALL_CONTRAIL=${INSTALL_CONTRAIL:-0}

if [ -z "${SERVER_HOST}" ]; then
  echo "You need to provide server host"
  exit -1
fi

cat << EOF > example_config.yaml
provider_config:
  kvm:
    image: CentOS-7-x86_64-GenericCloud-1710.qcow2.xz
    image_url: https://cloud.centos.org/centos/7/images/
    ssh_pwd: c0ntrail123
    ssh_user: root
    ssh_public_key:
    ssh_private_key:
    vcpu: 8
    vram: 64000
    vdisk: 300G
    subnet_prefix: ${NETWORK_PREFIX}.0
    subnet_netmask: 255.255.255.0
    gateway: ${NETWORK_PREFIX}.1
    nameserver: 8.8.8.8
    ntpserver: ${NETWORK_PREFIX}.1
    domainsuffix: local
instances:
  kvm${VMS_LAST_OCTET_PREFIX}\${INSTANCE_NUMBER}:
    provider: kvm
    host: \${SERVER_IP}
    bridge: default
    ip: ${NETWORK_PREFIX}.${VMS_LAST_OCTET_PREFIX}\${INSTANCE_NUMBER}
    roles:
        config_database:
        config:
        control:
        analytics_database:
        analytics:
        webui:
        openstack:
        vrouter:
        openstack_compute:
contrail_configuration:
  CONTAINER_REGISTRY: ${CONTRAIL_REGISTRY}
  CONTRAIL_VERSION: ${CONTRAIL_VERSION}
  UPGRADE_KERNEL: true
  RABBITMQ_NODE_PORT: 5673
  AUTH_MODE: keystone
  KEYSTONE_AUTH_URL_VERSION: /v3
  KEYSTONE_AUTH_ADMIN_PASSWORD: contrail123
  CLOUD_ORCHESTRATOR: openstack
kolla_config:
  commit_id: ${KOLLA_COMMIT}
  customize:
    nova.conf: |
      [libvirt]
      virt_type=qemu
      cpu_mode=none
  kolla_globals:
    network_interface: "eth0"
    kolla_internal_vip_address: "${NETWORK_PREFIX}.${VMS_LAST_OCTET_PREFIX}\${INSTANCE_NUMBER}"
    kolla_external_vip_address: "${NETWORK_PREFIX}.${VMS_LAST_OCTET_PREFIX}\${INSTANCE_NUMBER}"
    enable_haproxy: "no"
    enable_ironic: "no"
    enable_swift: "no"
EOF

yum install -y epel-release
yum install -y ${REQUIRED_PACKAGES}

cat << EOF > /etc/ntp.conf
driftfile /var/lib/ntp/drift
pool 0.pool.ntp.org iburst
pool 1.pool.ntp.org iburst
pool 2.pool.ntp.org iburst
pool 3.pool.ntp.org iburst
restrict 127.0.0.1
restrict -6 ::1
restrict ${NETWORK_PREFIX}.0 mask 255.255.255.0 nomodify notrap nopeer
includefile /etc/ntp/crypto/pw
keys /etc/ntp/keys
EOF

service libvirtd start
service ntpd restart
iptables -I INPUT -p udp --dport 123 -j ACCEPT

echo > ~/.ssh/known_hosts

for i in $(seq 1 ${NUMBER_OF_VMS}); do
  if [[ "${ANSIBLE_DEPLOYER_CLEANUP}" =~ ^[yY]|[yY][eE][sS]|1|[tT][rR][uU][eE]$ ]]; then
    rm -fr ansible_contrail_deployer_${i}
  fi

  git clone ${ANSIBLE_DEPLOYER_URL} ansible_contrail_deployer_${i}
  cd ansible_contrail_deployer_${i}
  git reset --hard ${ANSIBLE_DEPLOYER_COMMIT}
  cd ..

  export INSTANCE_NUMBER=${i}
  export SERVER_IP=${SERVER_HOST}

  envsubst < example_config.yaml > ansible_contrail_deployer_${i}/config/instances.yaml

  cd ansible_contrail_deployer_${i}
  if [[ "${BOOTSTRAP}" =~ ^[yY]|[yY][eE][sS]|1|[tT][rR][uU][eE]$ ]]; then
    rm -f /tmp/provision_${i}.log /tmp/configure_${i}.log /tmp/install_${i}.log
    ansible-playbook -i inventory/ playbooks/provision_instances.yml >> /tmp/provision_${i}.log
    ansible-playbook -i inventory/ playbooks/configure_instances.yml >> /tmp/configure_${i}.log
    ansible-playbook -i inventory/ -e orchestrator=openstack -e skip_contrail=yes playbooks/install_contrail.yml >> /tmp/install_${i}.log
  fi
  if [[ "${INSTALL_CONTRAIL}" =~ ^[yY]|[yY][eE][sS]|1|[tT][rR][uU][eE]$ ]]; then
    rm -f /tmp/install_contrail_${i}.log
    screen -S ansible_deployer${i} -dm bash -c "ansible-playbook -i inventory/ -e orchestrator=openstack -e skip_openstack=yes playbooks/install_contrail.yml >> /tmp/install_contrail_${i}.log; exec bash"
  fi
  cd ..
done
