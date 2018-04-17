cd /tmp
wget https://cloud-images.ubuntu.com/trusty/current/trusty-server-cloudimg-amd64-disk1.img

virt-customize --password ubuntu:password:contrail123 -a /tmp/trusty-server-cloudimg-amd64-disk1.img --run-command "add-apt-repository ppa:cz.nic-labs/bird" --run-command  "apt-get update" --run-command "apt-get -y --force-yes install bird apache2" --run-command "sed -i 's/PasswordAuthentication no/PasswordAuthenticationn yes/' /etc/ssh/sshd_config" --run-command "curl https://raw.githubusercontent.com/PrzemekGrygiel/contrail-lab/master/bird.template > /root/bird.template" --run-command "curl https://raw.githubusercontent.com/PrzemekGrygiel/contrail-lab/master/rc.local > /etc/rc.local"

source  /etc/kolla/admin-openrc.sh 
openstack image create --disk-format qcow2 --container-format bare --public --file ./trusty-server-cloudimg-amd64-disk1.img ubuntu-lab
openstack flavor create --ram 2048 --disk 5 --vcpus 1 m1.small
#openstack stack create -t create_vm.yaml -e env.yaml bgpaas_lab