#!/bin/bash
#
echo "Juniper Networks vMX Docker Container (unsupported prototype)"
echo ""


set -e	#  Exit immediately if a command exits with a non-zero status.

#export qemu=/qemu/x86_64-softmmu/qemu-system-x86_64
qemu=/usr/local/bin/qemu-system-x86_64
snabb=/usr/local/bin/snabb  # only used for Intel 82599 10GE ports

# mount hugetables, remove directory if this isn't possible due
# to lack of privilege level. A check for the diretory is done further down
mkdir /hugetlbfs && mount -t hugetlbfs none /hugetlbfs || rmdir /hugetlbfs

# check that we are called with enough privileges and env variables set
if [ ! -d "/hugetlbfs" -o ! -d "/u" ]; then
  cat README.md
  exit 1
fi

echo -n "Checking system for hugepages ..."
HUGEPAGES=`cat /proc/sys/vm/nr_hugepages`
if [ "2500" -gt "$HUGEPAGES" ]; then
  echo ""
  echo ""
  echo "ERROR: Not enough hugepages reserved!"
  echo ""
  echo "Please reserve at least 2500 hugepages to run vMX."
  echo "You can do this as root with the following command:"
  echo ""
  echo "# echo 5000 > /proc/sys/vm/nr_hugepages"
  echo ""
  echo "Make it permanent by adding 'hugepages=5000' to GRUB_CMDLINE_LINUX_DEFAULT"
  echo "in /etc/default/grub, followed by running 'update-grub'"
  echo ""
  exit 1
fi
echo " ok ($HUGEPAGES)"

#This is not true anymore, as some releases have different VCP mem. 
#so lets do it differently. Default it will be 2000; however, trying to get right one.
VCPMEM="${VCPMEM:-2000}"
MEM="${MEM:-8000}"
VCPU="${VCPU:-7}"

if [ ! -f "/u/$TAR" -a -z "$VCP" ]; then
  echo "Please set env TAR with a URL to download vmx-<rel>.tgz:"
  echo "docker run .... --env TAR=\"\" ..."
  echo "or specify a RE/VCP image via --env VCP=<jinstall*.img>"
  echo "You can download the latest release from Juniper Networks at"
  echo "http://www.juniper.net/support/downloads/?p=vmx"
  echo "(Requires authentication)"
  exit 1
fi

if [ ! -z "`cat /proc/cpuinfo|grep f16c|grep fsgsbase`" ]; then
  CPU="-cpu SandyBridge,+rdrand,+fsgsbase,+f16c"
  echo "CPU supports high performance PFE image"
else
  CPU=""
  echo "CPU doesn't supports high performance PFE image, using lite version"
fi

#---------------------------------------------------------------------------
function cleanup {

  echo ""
  echo ""
  echo "vMX terminated."
  echo ""
  echo "cleaning up interfaces and bridges ..."

  echo "Removing physical interfaces from bridges ..."
  for INT in $INTS; do
    BRIDGE=`echo "$INT"|cut -d: -f1`
    INTERFACE=`echo "$INT"|cut -d: -f2`
    $(delif_from_bridge $BRIDGE $INTERFACE)
  done
  echo "Removing tap interfaces from bridges ..."
  for TAP in $TAPS; do
    BRIDGE=`echo "$TAP"|cut -d: -f1`
    TAP=`echo "$TAP"|cut -d: -f2`

    echo "delete interface $TAP from $BRIDGE"
    $(delif_from_bridge $BRIDGE $TAP)

    echo "delete tap interface $TAP"
    $(delete_tap_if $TAP) || echo "WARNING: trouble deleting tap $TAP"
  done

  echo "Deleting bridges ..."
  for BRIDGE in $BRIDGES; do
    $(delete_bridge $BRIDGE)
  done

  echo "Deleting fxp0 and internal links and bridges"
  if [ ! -z "$BRINT" ]; then
    $(delif_from_bridge $BRINT $VCPINT)
    $(delete_tap_if $VCPINT) || echo "WARNING: trouble deleting tap $VCPINT"
    $(delete_tap_if $VFPINT) || echo "WARNING: trouble deleting tap $VFPINT"
    $(delete_bridge $BRINT)
  fi

  if [ ! -z "$BRMGMT" ]; then
    if [ ! -z "$VCPMGMT" ]; then
      $(delif_from_bridge $BRMGMT $VCPMGMT)
      $(delete_tap_if $VCPMGMT) || echo "WARNING: trouble deleting tap $VCPMGMT"
    fi
    if [ ! -z "$VFPMGMT" ]; then
      $(delif_from_bridge $BRMGMT $VFPMGMT)
      $(delete_tap_if $VFPMGMT) || echo "WARNING: trouble deleting tap $VFPMGMT"
    fi
  fi
  echo "done"

  if [ ! -z "$PCIDEVS" ]; then
    echo "Giving 10G ports back to linux kernel"
    for PCI in $PCIDEVS; do
      echo -n "$PCI" > /sys/bus/pci/drivers/ixgbe/bind
    done
  fi
  trap - EXIT SIGINT SIGTERM
  exit 0
}
#---------------------------------------------------------------------------

trap cleanup EXIT SIGINT SIGTERM

function create_bridge {
  if [ -z "`brctl show|grep $11`" ]; then
    brctl addbr $1
    ip link set $1 up
  fi
}

function addif_to_bridge {
  brctl addif $1 $2
}

function delif_from_bridge {
  brctl delif $1 $2
}

function delete_bridge {
  if [ "2" == "`brctl show $1|wc -l`" ]; then
    ip link set $1 down
    brctl delbr $1
  fi
}

function create_tap_if {
  ip tuntap add dev $1 mode tap
  ip link set $1 up promisc on
}

function delete_tap_if {
  ip tuntap del mode tap dev $1
}

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

function find_free_port {
# input: first port#, will try the next 100
  low=$1
  high=$(($low + 100))
  while :; do
    for (( port = low ; port <= high ; port++ )); do
      netstat -ntpl | grep [0-9]:$port -q || break 2
    done
  done
  echo $port
}

# Create unique 4 digit ID used for this vMX in interface names
ID=`printf '%02x%02x' $[RANDOM%256] $[RANDOM%256]`
N=0	# added to each tap interface to make them unique

# Check if we run with --net=host or not by checking the existense of
# the bridge docker0:

if [ -z "`ifconfig docker0 >/dev/null 2>/dev/null && echo notfound`" ]; then
  # Running without --net=host. Create local bridge for MGMT and place
  # eth0 in it.
  BRMGMT="br0"
  MYIP=`ifconfig | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p'`
  GATEWAY=`ip -4 route list 0/0 |cut -d' ' -f3`
  ip addr flush dev eth0
  brctl addbr $BRMGMT
  ip link set $BRMGMT up
  ip addr add $MYIP/16 dev br0
  route add default gw $GATEWAY
  brctl addif $BRMGMT eth0
else
  BRMGMT="docker0"
fi

# Create tap interfaces for mgmt and internal connection
VCPMGMT="vcpm$ID$N"
N=$((N + 1))
$(create_tap_if $VCPMGMT)

VCPINT="vcpi$ID$N"
N=$((N + 1))
$(create_tap_if $VCPINT)

VFPMGMT="vfpm$ID$N"
N=$((N + 1))
$(create_tap_if $VFPMGMT)

VFPINT="vfpi$ID$N"
N=$((N + 1))
$(create_tap_if $VFPINT)

# Create internal bridge between VCP and VFP
BRINT="brint$ID"
$(create_bridge $BRINT)

# Add internal tap interface to internal bridge
$(addif_to_bridge $BRINT $VCPINT)
$(addif_to_bridge $BRINT $VFPINT)

# Add external (mgmt) tap interfaces to docker0
if [ ! -z "$BRMGMT" ]; then
  $(addif_to_bridge $BRMGMT $VCPMGMT)
  $(addif_to_bridge $BRMGMT $VFPMGMT)
fi

port_n=0	# added to each tap interface to make them unique

# =======================================================
# check the list of interfaces provided in --env DEV=
# to keep track of the bridges and tap interfaces
# for the data ports for cleanup before exiting

BRIDGES=""
TAPS=""
INTS=""
NETDEVS=""    # build netdev list for VFP qemu
PCIDEVS=""

echo "Building virtual interfaces and bridges ..."

for DEV in $DEV; do # ============= loop thru interfaces start

  # check if we have been given a bridge or interface
  # If its an interface, we need to first create a unique bridge
  # followed by creating a tap interface and place the tap and
  # interface in it.
  # If its a bridge, we simply create a tap interface and add it
  # to the bridge

  INT=""
  BRIDGE=""

  # check if the interface given looks like a PCI address
  # Right now I simply check for length == 12. Probably needs
  # a more sophisticated check to avoid confusion with long bridge or
  # interface names

  if [ "12" -eq "${#DEV}" ]; then
    # cool. We got a PCI address. Lets check if its valid
    if [ -L /sys/bus/pci/drivers/ixgbe/$DEV ]; then
      echo "$DEV is a supported Intel 82599-based 10G port."
      # add $DEV to list
      PCIDEVS="$PCIDEVS $DEV"
      macaddr=`printf '00:49:BA:%02X:%02X:%02X\n' $[RANDOM%256] $[RANDOM%256] $[RANDOM%256]`
      NETDEVS="$NETDEVS -chardev socket,id=char$port_n,path=./xe$port_n.socket,server \
        -netdev type=vhost-user,id=net$port_n,chardev=char$port_n \
        -device virtio-net-pci,netdev=net$port_n,mac=$macaddr"

      cat > xe${port_n}.cfg <<EOF
return {
  {
    port_id = "xe${port_n}",
    mac_address = nil
  }
}
EOF
      node=$(pci_node $DEV)
      numactl="numactl --cpunodebind=$node --membind=$node"
      cat > launch_snabb_xe${port_n}.sh <<EOF
#!/bin/bash
SNABB=$snabb
CONFIG=xe${port_n}.cfg
MAC=$macaddr

while :
do
  # check if there is a snabb binary available in the mounted directory.
  # use that one if yes
  if [ -f /u/snabb ]; then
    SNABB=/u/snabb
  fi
  # check if there is a snabb config file in the mounted directory.
  # If yes, use it and replace the dummy mac with the one assigned to the interface
  if [ -f /u/\$CONFIG ]; then
    cp /u/\$CONFIG .
    sed -i "s/00:00:00:00:00:00/$macaddr/" \$CONFIG
  fi
  $numactl \$SNABB snabbnfv traffic -k 10 -D 0 $DEV \$CONFIG %s.socket
  echo "waiting 5 seconds before relaunch ..."
  sleep 5
done

EOF
      chmod a+rx launch_snabb_xe${port_n}.sh
      port_n=$(($port_n + 1))
    else
      echo "Error: $DEV isn't an Intel 82599-based 10G port!"
      exit 1
    fi

  else

    TAP="ge$ID$port_n"
    $(create_tap_if $TAP)

    if [ -z "`ifconfig $DEV > /dev/null 2>/dev/null || echo found`" ]; then
      # check if its eventually an existing bridge
      echo "interface $DEV found"
      if [ ! -z "`brctl show $DEV 2>&1 | grep \"No such device\"`" ]; then
        INT=$DEV # nope, we have a physical interface here
        echo "$DEV is a physical interface"
      else
        echo "$DEV is an existing bridge"
        BRIDGE="$DEV"
      fi
    else
      # we know now $DEV is or will be a bridge. Check if it exists
      # already
      BRIDGE=$DEV
      if [ ! -z "`brctl show $DEV 2>&1 | grep \"No such device\"`" ]; then
        # doesn't exist yet. Lets create it
        echo "need to create bridge $BRIDGE"
        $(create_bridge $BRIDGE)
      fi
    fi

    if [ -z "$BRIDGE" ]; then
      BRIDGE="br$ID$port_n"
      $(create_bridge $BRIDGE)
    fi

#    echo "DEV=$DEV INT=$INT BRIDGE=$BRIDGE TAP=$TAP"

    $(addif_to_bridge $BRIDGE $TAP)

    if [ ! -z "$INT" ]; then
      $(addif_to_bridge $BRIDGE $INT)
    fi

    # track what we use for cleanup before exit
    BRIDGES="$BRIDGES $BRIDGE"
    TAPS="$TAPS $BRIDGE:$TAP"
    if [ ! -z "$INT" ]; then
      INTS="$INTS $BRIDGE:$INT"
    fi

    macaddr=`printf '00:49:BA:%02X:%02X:%02X\n' $[RANDOM%256] $[RANDOM%256] $[RANDOM%256]`
    NETDEVS="$NETDEVS -netdev tap,id=net$port_n,ifname=$TAP,script=no,downscript=no \
        -device virtio-net-pci,netdev=net$port_n,mac=$macaddr"
    port_n=$(($port_n + 1))

  fi

done
# ===================================== loop thru interfaces done

echo "=================================="
echo "BRIDGES: $BRIDGES"
echo "TAPS:    $TAPS"
echo "INTS:    $INTS"
echo "PCIDEVS: $PCIDEVS"
if [ ! -z "$VFPIMAGE" ]; then
  echo "=================================="
  echo "vPFE using ${MEM}MB and $VCPU vCPUs"
fi
echo "=================================="


if [ ! -z "$TAR" ]; then
  echo -n "extracting VM's from $TAR ... "
  # adding qcow2 as well for 16.1+
  tar -zxf /u/$TAR -C /tmp/ --wildcards vmx*/images/*qcow2 --wildcards vmx*/images/*img
  echo ""
  HDDIMAGE="`ls /tmp/vmx*/images/vmxhdd.img`"
else
  echo "Creating an empty vmxhdd.img ..."
  qemu-img create -f qcow2 /tmp/vmxhdd.img 2G
  HDDIMAGE="/tmp/vmxhdd.img"
fi

if [ ! -z "$VCP" ]; then
  cp /u/$VCP .
  VCPIMAGE="$VCP"
else
  VCPIMAGE="`ls /tmp/vmx*/images/jinstall64-vmx*img 2> /dev/null`" || true
  if [ -z $VCPIMAGE ]; then   #it is ok, as 16.1+ has *.qcow2
   echo "`ls /tmp/vmx*/images/*`" 
   VCPIMAGE="`ls /tmp/vmx*/images/junos-vmx*qcow2 2> /dev/null`" || true

  fi
fi

VFPIMAGE="`ls /tmp/vmx*/images/vFPC*img 2> /dev/null`" || true   # its ok not to have one ..
if [ -z "$VFPIMAGE" ]; then
  # not a 15.1F image, so lets see if we find the 14.1 based vPFE image ...
  VFPIMAGE="`ls /tmp/vmx*/images/vPFE-lite-*img 2> /dev/null`" || true
  # This will allow the use of the high performance image if
  if [ ! -z "$CPU" -a  ".lite" != ".$PFE" ]; then
    VFPIMAGE="`ls /tmp/vmx*/images/vPFE-2*img 2> /dev/null`" || true
  fi
fi

# Lets build a metadata image. Required for 15.1F3 and higher releases.
# It "tells" the vRE to work as a vMX with a vPFE and one can place a config
# file in it.

mkdir config_drive
mkdir config_drive/boot
mkdir config_drive/config
cat > config_drive/boot/loader.conf <<EOF
vmtype="0"
vm_retype="RE-VMX"
vm_i2cid="0xBAA"
vm_chassis_i2cid="161"
vm_instance="0"
EOF
if [ ! -z "$CONFIG" ]; then
  if [ -f "/u/$CONFIG" ]; then
    cp /u/$CONFIG config_drive/config/juniper.conf
  else
    echo "Error: Can't find config file $CONFIG"
    cleanup
  fi
fi

cd config_drive
tar zcf vmm-config.tgz *
rm -rf boot config
cd ..
# Create our own metadrive image, so we can use a junos config file
# 100MB should be enough.
dd if=/dev/zero of=metadata.img bs=1M count=100
mkfs.vfat metadata.img
mount -o loop metadata.img /mnt
cp config_drive/vmm-config.tgz /mnt
umount /mnt
METADATA="-usb -usbdevice disk:format=raw:metadata.img -smbios type=0,vendor=Juniper -smbios type=1,manufacturer=Juniper,product=VM-vcp_vmx2-161-re-0,version=0.1.0"

if [ -z $VCPIMAGE ] || [ ! -f $VCPIMAGE ]; then
  echo "Can't find jinstall64-vmx*img or junos-vmx*qcow2 in tar file"
  exit 1
fi

if [ ! -f $VFPIMAGE ]; then
  echo "WARNING: No vPFE image provided. Running in RE/VCP only mode"
fi

if [ ! -f $HDDIMAGE ]; then
  echo "Can't find vmxhdd*img in tar file"
  exit 1
fi

echo "VCP image: $VCPIMAGE"
echo "VFP image: $VFPIMAGE"
echo "hdd image: $HDDIMAGE"
echo "METADATA : $METADATA"

if [ -z "$DEV" ]; then
  echo "Please set env DEV with list of interfaces or bridges:"
  echo "docker run .... --env DEV=\"eth1 br5 \""
  exit 1
fi

tmux_session="vmx$ID"

# Launch Junos Control plane virtual image in the background and
# connect to the console via telnet port $consoleport if we have a config to
# send to it. Then open a telnet session to the console as the first
# tmux session, so its the main session a user see's.

macaddr1=`printf '00:49:BA:%02X:%02X:%02X\n' $[RANDOM%256] $[RANDOM%256] $[RANDOM%256]`
macaddr2=`printf '00:49:BA:%02X:%02X:%02X\n' $[RANDOM%256] $[RANDOM%256] $[RANDOM%256]`
vcp_pid="/var/tmp/vcp-$macaddr1.pid"
vcp_pid=$(echo $vcp_pid | tr ":" "-")

consoleport=$(find_free_port 8700)
vncdisplay=$(($(find_free_port 5901) - 5900))

RUNVCP="$qemu -M pc -smp 1 --enable-kvm -cpu host -m $VCPMEM \
  -drive if=ide,file=$VCPIMAGE -drive if=ide,file=$HDDIMAGE $METADATA \
  -device cirrus-vga,id=video0,bus=pci.0,addr=0x2 \
  -netdev tap,id=tc0,ifname=$VCPMGMT,script=no,downscript=no \
  -device e1000,netdev=tc0,mac=$macaddr1 \
  -netdev tap,id=tc1,ifname=$VCPINT,script=no,downscript=no \
  -device virtio-net-pci,netdev=tc1,mac=$macaddr2 \
  -chardev socket,id=charserial0,host=127.0.0.1,port=$consoleport,telnet,server,nowait \
  -device isa-serial,chardev=charserial0,id=serial0 \
  -pidfile $vcp_pid -vnc 127.0.0.1:$vncdisplay -daemonize"

echo "$RUNVCP" > runvcp.sh
chmod a+rx runvcp.sh

./runvcp.sh # launch VCP in the background

echo "waiting for login prompt ..."
/usr/bin/expect <<EOF
set timeout -1
spawn telnet localhost $consoleport
expect "login:"
EOF

# if we have a config file, use it to log in an set
if [ -f "/u/$CFG" ]; then
  printf "\033c"  # clear screen
  echo "Using config file /u/$CFG to provision the vMX ..."
  cat /u/$CFG | nc -t -i 1 -q 1 127.0.0.1 $consoleport
fi

tmux new-session -d -n "vcp" -s $tmux_session "telnet localhost $consoleport"

# Launch VFP
if [ ! -z "$VFPIMAGE" ]; then

  macaddr1=`printf '00:49:BA:%02X:%02X:%02X\n' $[RANDOM%256] $[RANDOM%256] $[RANDOM%256]`
  macaddr2=`printf '00:49:BA:%02X:%02X:%02X\n' $[RANDOM%256] $[RANDOM%256] $[RANDOM%256]`
  vfp_pid="/var/tmp/vfp-$macaddr1.pid"
  vfp_pid=$(echo $vfp_pid | tr ":" "-")

  # launch snabb drivers, if any
  for file in launch_snabb_xe*.sh
  do
    tmux new-window -a -d -n "${file:13:3}" -t $tmux_session ./$file
  done

  # we borrow the last $numactl in case of 10G ports. If there wasn't one
  # then this will be simply empty
  # TODO: once 15.1 for vMX is released with a fix for --cpu host, add this 
  # for increased performance. Can't really enable this for 14.1R4.5, because
  # it will break VFP 
  RUNVFP="$numactl $qemu -M pc -smp $VCPU --enable-kvm $CPU -m $MEM -numa node,memdev=mem \
    -object memory-backend-file,id=mem,size=${MEM}M,mem-path=/hugetlbfs,share=on \
    -drive if=ide,file=$VFPIMAGE \
    -netdev tap,id=tf0,ifname=$VFPMGMT,script=no,downscript=no \
    -device virtio-net-pci,netdev=tf0,mac=$macaddr1 \
    -netdev tap,id=tf1,ifname=$VFPINT,script=no,downscript=no \
    -device virtio-net-pci,netdev=tf1,mac=$macaddr2 -pidfile $vfp_pid \
    $NETDEVS -nographic"

  echo "$RUNVFP" > runvfp.sh
  chmod a+rx runvfp.sh

  tmux new-window -a -d -n "vfp" -t $tmux_session ./runvfp.sh

fi

# the following can be useful for debugging 
#tmux new-window -a -d -n "shell" -t $tmux_session "bash"

# DON'T detach from tmux when running the container! Use docker's ^P^Q to detach
tmux attach

# ==========================================================================
# User terminated tmux, lets kill all VM's too

echo "killing all VM's and snabb drivers ..."
kill `cat $vcp_pid` || true
kill `cat $vfp_pid` || true
pkill snabb || true

echo "waiting for vcp qemu to terminate ..."
while  true;
do
  if [ "1" == "`ps ax|grep qemu| grep $vcp_pid|wc -l`" ]; then
    break
  fi
  sleep 1
done

exit  # this will call cleanup, thanks to trap set earlier (hopefully)
