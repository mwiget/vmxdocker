#!/bin/bash
#
qemu=/usr/local/bin/qemu-system-x86_64
snabb=/usr/local/bin/snabb

#---------------------------------------------------------------------------
function show_help {
  cat <<EOF
Usage:

docker run --name <name> --rm [--volume \$PWD:/u:ro] \\
   --privileged -i -t marcelwiget/vmx[:version] \\
   -c <junos_config_file> [-l license_file] [-i identity] \\
   [-m <kbytes>] [-v <vcpu count>] <image> <pci-address> [<pci-address> ...]

[:version]       Container version. Defaults to :latest

 -v \$PWD:/u:ro   Required to access a file in the current directory
                 docker is executed from (ro forces read-only access)
                 The file will be copied from this location

 -i  ssh private key for user snabbvmx (required for license install and 
     special services like lw4o6 lwaftr)

 -l  license_file to be loaded at startup (requires user snabbvmx with ssh
     private key given via option -i)

 -v  Specify the number of virtual CPU's
 -m  Specify the amount of memory
 -d  enable debug messages during startup

<pci-address>    PCI Address of the Intel 825999 based 10GE port
                 Multiple ports can be specified, space separated
                 0000:00:00.0 can be used to create virtio port only
                 Alternatively, a linux bridge name can be specified, which
                 will be created unless already present

The running VM can be reached via VNC on port 5901 of the containers IP

Example:
docker run --name vmx1 --rm --privileged --net=host -v \$PWD:/u:ro \\
  -i -t marcelwiget/vmx:lwaftr -c vmx1.conf.txt -i snabbvmx.key \\
  -d jinstall64-vmx-15.1F3.11-domestic.img \\
  brxe0 brxe1 0000:05:00.0 0000:05:00.1

EOF
}

#---------------------------------------------------------------------------
function cleanup {

  set +e

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
      echo "removing $VCPMGMT from $BRMGMT ..."
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
      if [ "$PCI" != "0000:00:00.0" ]; then
        echo -n "$PCI" > /sys/bus/pci/drivers/ixgbe/bind 2>/dev/null
      fi
    done
  fi
  trap - EXIT SIGINT SIGTERM
  exit 0
}
#---------------------------------------------------------------------------

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

function create_mgmt_bridge {
  if [ -z "`ifconfig docker0 >/dev/null 2>/dev/null && echo notfound`" ]; then
    # Running without --net=host. Create local bridge for MGMT and place
    # eth0 in it.
    bridge="br0"
    myip=`ifconfig | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p'`
    gateway=`ip -4 route list 0/0 |cut -d' ' -f3`
    ip addr flush dev eth0
    brctl addbr $bridge
    ip link set $bridge up
    ip addr add $myip/16 dev br0
    route add default gw $gateway
    brctl addif $bridge eth0
  else
    bridge="docker0"
  fi
  echo $bridge
}

function virtual_routing_engine_image {
  # ok. We didn't get a URL, so this must be a file we can reach
  # via the mounted filesystem given via 'docker run --volume'
  image=$1
  if [ ! -e "/u/$image" ]; then
    >&2 echo "Can't access $image via mount point. Did you specify --volume \$PWD:/u:ro ?"
   exit 1
  fi

  # unpack images from the tar file (if it is one)
  if [[ "$image" =~ \.tgz$ ]]; then
    >&2 echo "extracting VM's from $image ..."
    tar -zxf /u/$image -C /tmp/ --wildcards vmx*/images/*img
    vcpimage="`ls /tmp/vmx*/images/jinstall64-vmx*img`"
  else
    cp /u/$image .
    vcpimage=$(basename $image)
  fi
  echo $vcpimage 
}

function mount_hugetables {
  # mount hugetables, remove directory if this isn't possible due
  # to lack of privilege level. A check for the diretory is done further down
  mkdir /hugetlbfs && mount -t hugetlbfs none /hugetlbfs || rmdir /hugetlbfs

  # check that we are called with enough privileges and env variables set
  if [ ! -d "/hugetlbfs" ]; then
    >&2 echo "Can't access /hugetlbfs. Did you specify --privileged ?"
    exit 1
  fi

  hugepages=`cat /proc/sys/vm/nr_hugepages`
  if [ "0" -gt "$hugepages" ]; then
    >&2 echo "No hugepages found. Did you specify --privileged ?"
    exit 1
  fi
}

function get_host_name_from_config {
  echo "$(grep "host-name " $1 2>/dev/null | awk '{print $2}' | cut -d';' -f1)"
}

function get_mgmt_ip {
  # find IP address of em0 or fxp0 in given config
  grep --after-context=10 'em0 {\|fxp0 {' $1 | while IFS= read -r line || [[ -n "$line" ]]; do
      ipaddr="$(echo $line | grep address | awk -F "[ /]" '{print $2}')"
      if [ ! -z "$ipaddr" ]; then
        echo "$ipaddr"
        break
      fi
  done
}

function extract_licenses {
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [ ! -z "$line" ]; then
      tmp="$(echo "$line" | cut -d' ' -f1)"
      if [ ! -z "$tmp" ]; then
        file=${tmp}.lic
        if [ $DEBUG -gt 0 ]; then
          >&2 echo "  writing license file $file ..."
        fi
        echo "$line" > $file
      else
        echo "$line" >> $file
      fi
    fi
  done < "$1"
}

function create_config_drive {
  mkdir config_drive
  mkdir config_drive/boot
  mkdir config_drive/config
  mkdir config_drive/config/license
  cat > config_drive/boot/loader.conf <<EOF
vmchtype="vmx"
vm_retype="$RETYPE"
vm_instance="0"
EOF
  cp /u/$CONFIG config_drive/config/juniper.conf
  # placing license files on the config drive isn't supported yet
  # but it is assumed, this is how it will work.
  if [ -f *.lic ]; then
    for f in *.lic; do
      cp $f config_drive/config/license
    done
  fi
  cd config_drive
  tar zcf vmm-config.tgz *
  rm -rf boot config
  cd ..
  # Create our own metadrive image, so we can use a junos config file
  # 100MB should be enough.
  dd if=/dev/zero of=metadata.img bs=1M count=100 >/dev/null 2>&1
  mkfs.vfat metadata.img >/dev/null 
  mount -o loop metadata.img /mnt
  cp config_drive/vmm-config.tgz /mnt
  umount /mnt
}

#==================================================================
# main()

echo "Juniper Networks vMX Docker Container (unsupported prototype)"
echo ""
DEBUG=0
while getopts "h?c:m:v:l:i:d" opt; do
  case "$opt" in
    h|\?)
      show_help
      exit 1
      ;;
    v)  VCPU=$OPTARG
      ;;
    m)  MEM=$OPTARG
      ;;
    c)  CONFIG=$OPTARG
      ;;
    l)  LICENSE=$OPTARG
      ;;
    i)  IDENTITY=$OPTARG
      ;;
    d)  DEBUG=$((DEBUG + 1))
      ;;
  esac
done

shift "$((OPTIND-1))"

# first parameter is the vMX tar file or VM image, http/https URL is fine too
# if its missing, docker seems to put the container image name in $1, check
# for it and print the help message and exit
image=$1
shift

if [ "$image" == "vmx" ]; then
  show_help
  exit 1
fi 

set -e	#  Exit immediately if a command exits with a non-zero status.
trap cleanup EXIT SIGINT SIGTERM

VCPIMAGE=$(virtual_routing_engine_image $image)

# if a tar file was given, above func will have extracted the image into /tmp
VFPIMAGE="`ls /tmp/vmx*/images/vFPC*img 2>/dev/null`" || true   # its ok not to have one ..
if [ -z "$VFPIMAGE" ]; then
  echo "Running in vRR mode (without vPFE)"
  VCPMEM="${MEM:-2000}"
  VCPVCPU="${VCPU:-1}"
  echo "Creating empty vmxhdd.img for vRE ..."
  qemu-img create -f qcow2 /tmp/vmxhdd.img 2G >/dev/null
  HDDIMAGE="/tmp/vmxhdd.img"
  RETYPE="RE-VRR"
  SMBIOS=""
  INTNR=1	# added to each tap interface to make them unique
  INTID="em"
else
  VCPMEM=2000
  VCPVCPU=1
  VFPMEM="${MEM:-8000}"
  VFPVCPU="${VCPU:-3}"
  HDDIMAGE="`ls /tmp/vmx*/images/vmxhdd.img`"
  RETYPE="RE-VMX"
  SMBIOS="-smbios type=0,vendor=Juniper -smbios type=1,manufacturer=Juniper,product=VM-vcp_vmx2-161-re-0,version=0.1.0"
  INTNR=0	# added to each tap interface to make them unique
  INTID="xe"
fi

NAME=$(get_host_name_from_config /u/$CONFIG)
MGMTIP=$(get_mgmt_ip /u/$CONFIG)

BRMGMT=$(create_mgmt_bridge)

if [ $DEBUG -gt 0 ]; then
  cat <<EOF

  NAME=$NAME MGMTIP=$MGMTIP BRMGMT=$BRMGMT
  vRE : $VCPIMAGE with ${VCPMEM}kB and $VCPVCPU vcpu(s)
  vPFE: $VFPIMAGE with ${VFPMEM}kB and $VFPVCPU vcpu(s)
  config=$CONFIG license=$LICENSE identity=$IDENTITY

EOF
fi

echo "Checking system for hugepages ..."
$(mount_hugetables)

if [ -f /u/$LICENSE ]; then
  echo "Extract licenses from $LICENSE"
  $(extract_licenses /u/$LICENSE)
  # placing license files on config drive isn't supported yet,
  # so until then, lets create and launch a little helper that
  # will transfer the license file and load it.
  if [ -f /u/$IDENTITY ]; then
    cat > add-license.sh <<EOF
#!/bin/bash
while true; do
  scp -o StrictHostKeyChecking=no -i /u/$IDENTITY /u/$LICENSE snabbvmx@$MGMTIP:
  if [ \$? == 0 ]; then
    echo "transfer successful"
    break;
  fi
  echo "sleeping 5 seconds ..."
  sleep 5
done
echo "loading license file ..."
ssh -o StrictHostKeyChecking=no -i /u/$IDENTITY snabbvmx@$MGMTIP "request system license add $LICENSE"
if [ ! \$? == 0 ]; then
  echo "command failed"
  sleep 600
fi
EOF
    chmod a+rx add-license.sh
  fi
fi

echo "Creating config drive (metadata.img) ..."
$(create_config_drive)

echo "Create bridges and tap interfaces ..."
# Create unique 4 digit ID used for this vMX in interface names
ID=`printf '%02x%02x' $[RANDOM%256] $[RANDOM%256]`

# Create tap interfaces for mgmt and internal connection
N=0
VCPMGMT="vcpm$ID$N"
N=$((N + 1))
$(create_tap_if $VCPMGMT)
$(addif_to_bridge $BRMGMT $VCPMGMT)

if [ ! -z "$VFPIMAGE" ]; then
  VCPINT="vcpi$ID$N"
  N=$((N + 1))
  $(create_tap_if $VCPINT)

  VFPMGMT="vfpm$ID$N"
  N=$((N + 1))
  $(create_tap_if $VFPMGMT)
  $(addif_to_bridge $BRMGMT $VFPMGMT)

  VFPINT="vfpi$ID$N"
  N=$((N + 1))
  $(create_tap_if $VFPINT)

  # Create internal bridge between VCP and VFP
  # and add internal tap interfaces
  BRINT="brint$ID"
  $(create_bridge $BRINT)
  $(addif_to_bridge $BRINT $VCPINT)
  $(addif_to_bridge $BRINT $VFPINT)
fi

echo "BRMGMT=$BRMGMT VCPMGMT=$VCPMGMT"
echo "Building virtual interfaces and bridges for $@ ..."

MACP=$(printf "04:%02X:%02X:%02X" $[RANDOM%256] $[RANDOM%256] $[RANDOM%256])

for DEV in $@; do # ============= loop thru interfaces start

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
    # add $DEV to list
    PCIDEVS="$PCIDEVS $DEV"
    macaddr=$MACP:00:$(printf '%02X'  $INTNR)
    macaddr=`cat /sys/bus/pci/drivers/ixgbe/$DEV/net/*/address || echo $macaddr`
    NETDEVS="$NETDEVS -chardev socket,id=char$INTNR,path=./${INTID}$INTNR.socket,server \
        -netdev type=vhost-user,id=net$INTNR,chardev=char$INTNR \
        -device virtio-net-pci,netdev=net$INTNR,mac=$macaddr"

    echo "$DEV" > pci_${INTID}${INTNR} 
    echo "$macaddr" > mac_${INTID}${INTNR} 

    cat > ${INTID}${INTNR}.cfg <<EOF
return {
  {
    port_id = "${INTID}${INTNR}",
    mac_address = nil
  }
}
EOF
    node=$(pci_node $DEV)
    numactl="numactl --cpunodebind=$node --membind=$node"
    cat > launch_snabb_${INTID}${INTNR}.sh <<EOF
#!/bin/bash
while :
do
  # check if there is a snabb binary available in the mounted directory.
  # use that one if yes
  SNABB=$snabb
  if [ -f /u/snabb ]; then
    cp /u/snabb /tmp/ 2>/dev/null
    SNABB=/tmp/snabb
  fi
  # check if this port is assigned to snabbvmx-{service}-{ifname1}-{ifname2}
  IFNAME=${INTID}${INTNR}
  groupname="\$(grep snabbvmx /u/$CONFIG | grep \$IFNAME | awk '{print \$1}')"
  if [ ! -z "\$groupname" ]; then
    SERVICE="\$(echo "\$groupname" | cut -f2 -d-)"
    IFNAME1="\$(echo "\$groupname" | cut -f3 -d-)"
    IFNAME2="\$(echo "\$groupname" | cut -f4 -d- | cut -f1 -d' ')"
    if [ x\$IFNAME == x\$IFNAME1 ]; then
      if [ -z "\$IFNAME2" ]; then
        echo "launch snabbvmx for \$IFNAME1 ..."
        $numactl \$SNABB snabbvmx \$SERVICE --conf \${groupname}.cfg --v1id \$IFNAME1 --v1pci \`cat pci_\$IFNAME1\` --v1mac \`cat mac_\$IFNAME1\` --sock %s.socket
      else
        # echo "port in use by snabbvmx. Sleeping for 30 seconds ..."
        sleep 30
      fi
    elif [ x\$IFNAME == x\$IFNAME2 ]; then
      echo "launch snabbvmx for \$IFNAME1 and \$IFNAME2 ..."
      $numactl \$SNABB snabbvmx \$SERVICE --conf \${groupname}.cfg --v1id \$IFNAME1 --v1pci \`cat pci_\$IFNAME1\` --v1mac \`cat mac_\$IFNAME1\` --v2id \$IFNAME2 --v2pci \`cat pci_\$IFNAME2\` --v2mac \`cat mac_\$IFNAME2\` --sock %s.socket
    fi
  else
    echo "launch snabbnfv for \$IFNAME ..."
    $numactl \$SNABB snabbnfv traffic -D 0 -k 0 -l 0  $DEV \$IFNAME.cfg %s.socket
  fi
  sleep 5
done

EOF
    chmod a+rx launch_snabb_${INTID}${INTNR}.sh

  else

    TAP="ge$ID$INTNR"
    $(create_tap_if $TAP)

    if [ -z "`ifconfig $DEV > /dev/null 2>/dev/null || echo found`" ]; then
      # check if its eventually an existing bridge
      >&2 echo "interface $DEV found"
      if [ ! -z "`brctl show $DEV 2>&1 | grep \"No such device\"`" ]; then
        INT=$DEV # nope, we have a physical interface here
        >&2 echo "$DEV is a physical interface"
      else
        >&2 echo "$DEV is an existing bridge"
        BRIDGE="$DEV"
      fi
    else
      # we know now $DEV is or will be a bridge. Check if it exists
      # already
      BRIDGE=$DEV
      if [ ! -z "`brctl show $DEV 2>&1 | grep \"No such device\"`" ]; then
        # doesnt exist yet. Lets create it
        >&2 echo "need to create bridge $BRIDGE"
        $(create_bridge $BRIDGE)
      fi
    fi

    if [ -z "$BRIDGE" ]; then
      BRIDGE="br$ID$INTNR"
      $(create_bridge $BRIDGE)
    fi

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

    macaddr=$MACP:00:$(printf '%02X'  $INTNR)
    NETDEVS="$NETDEVS -netdev tap,id=net$INTNR,ifname=$TAP,script=no,downscript=no \
        -device virtio-net-pci,netdev=net$INTNR,mac=$macaddr"
  fi
  INTNR=$(($INTNR + 1))

done # ===================================== loop thru interfaces done

# Check config for snabbvmx group entries. If there are any
# run its manager to create an intial set of configs for snabbvmx 
sx="\$(grep ' snabbvmx-' /u/$CONFIG)"
if [ ! -z "\$sx" ] && [ -f ./snabbvmx_manager.pl ]; then
    ./snabbvmx_manager.pl /u/$CONFIG
fi

# launch snabb drivers, if any
for file in launch_snabb_${INTID}*.sh
do
  if [ -f $file ]; then
    ./$file &
  fi
done

if [ -f add-license.sh ]; then
  ./add-license.sh &
fi

# Launch a script that connects to the vRE and restarts snabbvmx whenever a commit has
# executed. Crude way to allow snabbvmx to learn about all config changes. This will
# be improved/removed when adding proper Junos JET/SDK support

if [ -f "/u/$IDENTITY" ]; then
    cp /u/$IDENTITY .
    cat > launch_snabbvmx_manager.sh <<EOF
#!/bin/bash
while :
do
  file=/u/snabbvmx_manager.??
  if [ ! -z "\$file" ] && [ -f \$file ]; then
    cp \$file /tmp/
    /tmp/snabbvmx_manager.?? $MGMTIP /u/$IDENTITY
  elif [ -f snabbvmx_manager.pl ]; then
    ./snabbvmx_manager.pl $MGMTIP /u/$IDENTITY
  fi
  sleep 5
done
EOF
  chmod a+rx launch_snabbvmx_manager.sh
  ./launch_snabbvmx_manager.sh &
fi

# Launch VFP on qemu in the background

if [ ! -z "$VFPIMAGE" ]; then

  # we borrow the last $numactl in case of 10G ports. If there wasn't one
  # then this will be simply empty

  if [ ! -z "`cat /proc/cpuinfo|grep f16c|grep fsgsbase`" ]; then
    CPU="-cpu SandyBridge,+rdrand,+fsgsbase,+f16c"
  else
    CPU=""
  fi

  consoleport=$(find_free_port 8700)
  vncdisplay=$(($(find_free_port 5901) - 5900))

  $numactl $qemu -M pc -smp $VFPVCPU --enable-kvm $CPU -m $VFPMEM -numa node,memdev=mem \
      -object memory-backend-file,id=mem,size=${VFPMEM}M,mem-path=/hugetlbfs,share=on \
      -drive if=ide,file=$VFPIMAGE \
      -netdev tap,id=tf0,ifname=$VFPMGMT,script=no,downscript=no \
      -device virtio-net-pci,netdev=tf0,mac=$MACP:19:01 \
      -netdev tap,id=tf1,ifname=$VFPINT,script=no,downscript=no \
      -device virtio-net-pci,netdev=tf1,mac=$MACP:19:02 \
      -device isa-serial,chardev=charserial0,id=serial0 \
      -chardev socket,id=charserial0,host=0.0.0.0,port=$consoleport,telnet,server,nowait \
      $NETDEVS -vnc :$vncdisplay -daemonize
fi

# Launch vRE on qemu in foreground. The container terminates when this app dies

if [ -z "$VFPIMAGE" ]; then
  NUMACTL="$numactl"
  NUMA="-numa node,memdev=mem -object memory-backend-file,id=mem,size=${VCPMEM}M,mem-path=/hugetlbfs,share=on"
  VCPNETDEVS="$NETDEVS"
else
  NUMACTL=""
  NUMA=""
  VCPNETDEVS="-netdev tap,id=tc1,ifname=$VCPINT,script=no,downscript=no \
      -device virtio-net-pci,netdev=tc1,mac=$MACP:18:02"
fi

METADATA="-usb -usbdevice disk:format=raw:metadata.img"
$NUMACTL $qemu -M pc -smp $VCPVCPU --enable-kvm -cpu host -m $VCPMEM $NUMA \
  $SMBIOS -drive if=ide,file=$VCPIMAGE -drive if=ide,file=$HDDIMAGE $METADATA \
  -device cirrus-vga,id=video0,bus=pci.0,addr=0x2 \
  -netdev tap,id=tc0,ifname=$VCPMGMT,script=no,downscript=no \
  -device e1000,netdev=tc0,mac=$MACP:18:01 $VCPNETDEVS -nographic

# ==========================================================================
# User terminated vcp, lets kill all VM's too

echo "killing vPFE and snabb drivers ..."
pkill qemu 2>/dev/null || true
pkill snabb || true

exit  # this will call cleanup, thanks to trap set earlier (hopefully)
