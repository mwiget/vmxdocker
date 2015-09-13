## Run Juniper Networks vMX in a Docker Container

### Overview

Juniper Networks [vMX](http://www.juniper.net/us/en/products-services/routing/mx-series/vmx/) virtual router can be installed on bare metal servers by running an installation script. A different solution is used here by creating a vmx Docker image that can be instantiated one or more times via Docker.

Each vMX container is given a list of interface, memory and vCPU count as well as an initial "zero touch" config plus an actual vMX distribution tar file (not provided here). 
The list of interfaces can contain virtual bridges and physical interfaces. The container will create required virtual bridges and attach physical interfaces as needed. Access to Intel 82599 based 10G Ethernet ports is handled via [Snabb Switch](https://github.com/SnabbCo/snabbswitch) by providing their PCI addresses instead of their interface names.
Based on the CPU's capability, the container runs either the standard or lite vPFE version (though its possible to force the use of the lite version).

This is currently in prototype stage and not recommended for production use. 

### Requirements

- Juniper Networks vMX distribution tar file. Download the latest vMX package from [http://www.juniper.net/support/downloads/?p=vmx#sw](http://www.juniper.net/support/downloads/?p=vmx#sw). A valud user account is required to access and download the file. This file must be made available to the container at startup via a mounted volume.
- Bare metal linux server with [Docker](https://www.docker.com) installed. Currently tested with Ubuntu 14.04 and 15.04. The kernel must have HugePages reserved by setting the following options in /etc/default/grub:

```
# cat /etc/default/grub
...
GRUB_CMDLINE_LINUX_DEFAULT="hugepages=12000"
...
# update-grub
# reboot
```

- Optional one or more Intel 82599 based 10G Ethernet ports. If used, the kernel must also have intel_iommu disabled:

```
# cat /etc/default/grub
...
GRUB_CMDLINE_LINUX_DEFAULT="hugepages=12000 intel_iommu=off"
...
# update-grub
# reboot
```

Qemu and snabb will get downloaded and compiled during the creation of the vmx docker image, hence there are no requirements on the server itself to have qemu or even developer tools installed.

### Download the vMX Image 

```
$ docker pull marcelwiget/vmx
$ docker images
REPOSITORY          TAG                 IMAGE ID            CREATED             VIRTUAL SIZE
marcelwiget/vmx     latest              a9c492840cd6        2 hours ago         432.3 MB
```

### Running the vMX Container

```
$ docker run --name vmx1 --rm --privileged --net=host \
  -v $PWD:/u:ro \
  --env TAR="vmx-14.1R5.4-1.tgz" \
  --env CFG="vmx1.cfg" \
  --env DEV="br0 br0" \
  --env PFE="lite" \
  --env MEM="5000" --env VCPU="5" \
  -i -t marcelwiget/vmx:latest
```

--name <name> 
The name must be unique across containers on the same server (e.g. vmx1)

--rm          
Destroy the container after termination (use -d to run as daemon instead)

-d            
Optional instead of --rm: Launch the Container in detached mode, making it possible to launch vMX fully unattended, while allowing the user to re-attach to the console via 'docker attach <name>'.

--privileged  
Required to allow creation of virtual bridges and tap interfaces and
 mounting of hugetables as a filesystem

--net=host    
Required to allow interface and virtual bridge access across containers and
between the host and containers. It also allows the binding of fxp0 to
docker0 (--net is optional when using 10GE ports only and fxp0 isn't required)

--v $PWD:/u   
Provides access to vmx tar and config file in the current directory from
within the container. The destination directory must always be /u and the
source directory can be adjusted as needed.

--env TAR="<filename>"    
Specify the filename of the vMX distribution tar file provided in /u to
the container (see --v option)

--env CFG="<filename>"    
Optional. Specify a config file that allows zero-touch provisioning of
the vMX. See an example further down. It is possible to set a license key
as well, but large configs should be transferred via netconf/ssh, because
the content of the file is sent to the virtual serial based console with
a 1 sec delay after each line.

--env DEV="<int1> <int2> ... <intN>"    
Space separated ordered list interface list given to the vMX. Possible
interfaces are physical network interfae names (e.g. eth0, p2p1, etc),
virtual bridges (which will be automatically created) and PCI addresses
of Intel 82599 based 10 Gigabit Ethernet ports. All interface types can
be mixed.

--env VCP="<vcp/jinstall*img>"    
Optional. Specify a virtual disk image for the VCP/vRE instead of taking it
from the TAR file. Can be used to run just the VCP image without any vPFE.

--env PFE="lite"    
Optional. If set to "lite", the lite version of the vPFE is used, even if
the CPU would allow the use of the high performance vPFE image from the
provided vMX distribution tar file.

--env MEM="<megabytes>"   
Optional. Set the amount of memory in MB given to the vPFE image.
default is 5000. The vRE image is hard set in launch.sh to 2000MB.

--env VCPU="<count>"  
Optional. Set the number of vCPU to be used by the vPFE. Default is 5.
The vRE image is hard set in launch.sh to 1 vCPU.

-i          
Keep STDIN open even if not attached. Required to keep tmux happy, even when
not attached.

-t          
Allocate a pseudo-TTY. Required for proper operation.


### Example: 2 vMX connected via virtual bridge

Launch 2 vMX containers named vmx1 and vmx2 with configs vmx1.cfg and vmx2.cfg and connect
them via a virtual bridge br0 (which will be automatically created and destroyed as needed):

  Router config files:

```
  $ cat vmx1.cfg
  root
  cli
  conf
  set interface fxp0.0 family inet address 172.17.42.5/24
  set system root-authentication plain-text-password
  juniper1
  juniper1
  set system host-name vmx1
  set system service ssh
  set system service netconf ssh
  set interface ge-0/0/0.0 family inet address 10.10.10.1/24
  commit and-quit
  mwiget-mba13:vmxdocker mwiget$ cat vmx2.cfg
  root
  cli
  conf
  set interface fxp0.0 family inet address 172.17.42.6/24
  set system root-authentication plain-text-password
  juniper1
  juniper1
  set system host-name vmx2
  set system service ssh
  set system service netconf ssh
  set interface ge-0/0/0.0 family inet address 10.10.10.2/24
  commit and-quit
```

Launch both vMX's:

```
  #!/bin/bash
  docker run --name vmx1 -d --privileged --net=host \
    -v $PWD:/u:ro \
    --env TAR="vmx-14.1R5.4-1.tgz" \
    --env CFG="vmx1.cfg" \
    --env DEV="br0" \
    --env PFE="lite" \
    --env MEM="5000" --env VCPU="5" \
    -i -t marcelwiget/vmx:latest

  docker run --name vmx2 -d --privileged --net=host \
    -v $PWD:/u:ro \
    --env TAR="vmx-14.1R5.4-1.tgz" \
    --env CFG="vmx2.cfg" \
    --env DEV="br0" \
    --env PFE="lite" \
    --env MEM="5000" --env VCPU="5" \
    -i -t marcelwiget/vmx:latest
```

  Attach to either vmx via

```
  $ docker attach vmx1
```

  It is also possible to launch the container directly in interactive mode, so
  progress can be monitored and the router console is accessible:

```
  docker run --name vmx1 --rm --privileged --net=host \
    -v $PWD:/u:ro \
    --env TAR="vmx-14.1R5.4-1.tgz" \
    --env CFG="vmx1.cfg" \
    --env DEV="br0" \
    --env PFE="lite" \
    --env MEM="5000" --env VCPU="5" \
    -i -t marcelwiget/vmx:latest
```

### Example vMX with two 82599 based 10GE ports

This example assumes a back-to-back cable to be connected between both ports.

```
  $ cat vmx3.cfg
  root
  cli
  conf
  set interface fxp0.0 family inet address 172.17.42.7/24
  set system root-authentication plain-text-password
  juniper1
  juniper1
  set system host-name vmx3
  set system service ssh
  set system service netconf ssh
  set interface ge-0/0/0.0 family inet address 10.10.10.1/24
  set routing-instance R1 instance-type virtual-router
  set routing-instance R1 interface ge-0/0/0.0
  set interface ge-0/0/1.0 family inet address 10.10.10.2/24
  set routing-instance R2 instance-type virtual-router
  set routing-instance R2 interface ge-0/0/1.0
  commit and-quit
```

Launch the vMX as follows:

```
  docker run --name vmx3 --rm --privileged --net=host \
    -v $PWD:/u:ro \
    --env TAR="vmx-14.1R5.4-1.tgz" \
    --env CFG="vmx3.cfg" \
    --env DEV="0000:04:00.0 0000:04:00.1" \
    --env PFE="lite" \
    --env MEM="5000" --env VCPU="5" \
    -i -t marcelwiget/vmx:latest
```

![title](https://github.com/mwiget/vmxdocker/blob/master/vmx3.png)

IMPORTANT: Instead of detaching from tmux via ^BD, use docker's method of detaching
from an interactive docker session via ^P^Q. Failing to do so will kill the vMX and
the virtual interfaces and bridges will be cleaned up.
See [http://docs.docker.com/articles/basics/](http://docs.docker.com/articles/basics/) for details. 

### Building the vMX Docker Image

- Clone this repository to the linux server

	```
	git clone https://github.com/mwiget/vmxdocker.git
	cd vmxdocker
	```
		
- Building the image

	```
	docker build -t marcelwiget/vmx:latest .
	```
	
	The vmx image is now available for launch:
	
	```
mwiget@va:~$ docker images
REPOSITORY          TAG                 IMAGE ID            CREATED             VIRTUAL SIZE
marcelwiget/vmx     latest              14bcc6fdcb4f        35 minutes ago      432.3 MB
```







