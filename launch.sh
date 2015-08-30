#!/bin/bash
set -e	#  Exit immediately if a command exits with a non-zero status.

mkdir /hugetlbfs && mount -t hugetlbfs none /hugetlbfs 

# create vmx mgmt bridge and tap interfaces
brctl addbr br-mgmt
ip link set br-mgmt up
ip tuntap add dev tapvcp mode tap
ip link set tapvcp up promisc on
brctl addif br-mgmt tapvcp
ip tuntap add dev tapvfp mode tap
ip link set tapvfp up promisc on
brctl addif br-mgmt tapvfp

# create vmx int bridge and tap interfaces
brctl addbr br-int
ip link set br-int up
ip tuntap add dev tapvcpi mode tap
ip link set tapvcpi up promisc on
brctl addif br-int tapvcpi
ip tuntap add dev tapvfpi mode tap
ip link set tapvfpi up promisc on
brctl addif br-int tapvfpi

export qemu=/qemu/x86_64-softmmu/qemu-system-x86_64
tmux_session=vmx

# Launch Junos Control plane virtual image first in tmux, so its 
# the default window shown when running the container in interactive mode

macaddr1=`printf '00:49:BA:%02X:%02X:%02X\n' $[RANDOM%256] $[RANDOM%256] $[RANDOM%256]`
macaddr2=`printf '00:49:BA:%02X:%02X:%02X\n' $[RANDOM%256] $[RANDOM%256] $[RANDOM%256]`

tmux new-session -d -n "vcp" -s $tmux_session \
  "$qemu -M pc -smp 1 --enable-kvm -cpu host -m 2048 \
  -drive if=ide,file=./vcp.img -drive if=ide,file=./hdd.img \
  -netdev tap,id=tc0,ifname=tapvcp,script=no,downscript=no \
  -device e1000,netdev=tc0,mac=$macaddr1 \
  -netdev tap,id=tc1,ifname=tapvcpi,script=no,downscript=no \
  -device virtio-net-pci,netdev=tc1,mac=$macaddr2 \
  -nographic"

if [ -z "$PCIDEVS" ]; then
  echo "Please set PCI address(es) of Intel 82599 10G ports:"
  echo "docker run .... --env PCIDEVS=\"0000:04:00.0 0000:04:00.1\""
  exit 1
fi

# Launch snabb for each 10G PCI address found in $PCIDEVS

function pci_node {
case "$1" in
  *:*:*.*)
    cpu=$(cat /sys/class/pci_bus/${1%:*}/cpulistaffinity | cut -d "-" -f 1)
    numactl -H | grep "cpus: $cpu" | cut -d " " -f 2
    ;;
  *)
    echo $1
    ;;
esac
                                                                                        }

export snabb=/snabbswitch/src/snabb

port_n=0
netdevs=""

# ======= Loop thru the PCI addresses to launch snabb daemons

for PCI in $PCIDEVS; do
  cat > xe${port_n}.cfg <<EOF
return {
  { 
    port_id = "xe${port_n}",
    mac_address = nil
  }
}
EOF

  node=$(pci_node $PCI)
  # generate random mac address
  macaddr=`printf '00:49:BA:%02X:%02X:%02X\n' $[RANDOM%256] $[RANDOM%256] $[RANDOM%256]`
  tmux new-window -a -d -n "snabb${port_id}" -t $tmux_session \
    "numactl --cpunodebind=$node --membind=$node \
    $snabb snabbnfv traffic -k 10 -D 0 $PCI xe${port_n}.cfg ./\%s.socket"
   
  netdevs="$netdevs -chardev socket,id=char$port_n,path=./xe$port_n.socket,server \
  -netdev type=vhost-user,id=net$port_n,chardev=char$port_n \
  -device virtio-net-pci,netdev=net$port_n,mac=$macaddr"
  port_n=$(expr $port_n + 1)  
done
# ======= end Loop

# Calculate how many vCPU's we need for the vPFE VM: 
# Start with 3, then add 1 vCPU per 10G port

vcpus=$(expr $port_n + 3)

# Allocate 6G of memory to vPFE
VFP_MEM=6200

macaddr1=`printf '00:49:BA:%02X:%02X:%02X\n' $[RANDOM%256] $[RANDOM%256] $[RANDOM%256]`
macaddr2=`printf '00:49:BA:%02X:%02X:%02X\n' $[RANDOM%256] $[RANDOM%256] $[RANDOM%256]`

tmux new-window -a -d -n "vfp" -t $tmux_session \
  "numactl --cpunodebind=$node --membind=$node \
  $qemu -M pc -smp $vcpus --enable-kvm  \
  -m $VFP_MEM -smp $vcpus -numa node,memdev=mem \
  -object memory-backend-file,id=mem,size=${VFP_MEM}M,mem-path=/hugetlbfs,share=on \
  -drive if=ide,file=./vfp.img \
  -netdev tap,id=tf0,ifname=tapvfp,script=no,downscript=no \
  -device virtio-net-pci,netdev=tf0,mac=$macaddr1 \
  -netdev tap,id=tf1,ifname=tapvfpi,script=no,downscript=no \
  -device virtio-net-pci,netdev=tf1,mac=$macaddr2 \
  $netdevs -nographic"

# DON'T detach from tmux when running the container! Use docker's ^P^Q to detach
exec tmux attach
