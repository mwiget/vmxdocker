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
$ docker pull marcelwiget/vmx:lwaftr
$ docker images
REPOSITORY          TAG                 IMAGE ID            CREATED             VIRTUAL SIZE
marcelwiget/vmx     latest              a9c492840cd6        2 hours ago         432.3 MB
```

### Running the vMX Container

```
$ docker run --name vmx1 --dti --privileged -v $PWD:/u:ro [--net=host] \
  [-p 8700] [-p 5901] marcelwiget/vmx:lwaftr -c vmx1.conf.txt \
  -l license.txt -i snabbvmx.key -v 3 -m 8000 \
  vmx-15.1F3.11.tgz 0000:05:00.0 0000:05:00.1 
```

--name <name> 
The name must be unique across containers on the same server (e.g. vmx1)

--dti          
Launches the container as daemon, keeping STDIN open in the background

--privileged  
Required to allow creation of virtual bridges and tap interfaces and
 mounting of hugetables as a filesystem

--net=host    
Required to allow interface and virtual bridge access across containers and
between the host and containers. It also allows the binding of fxp0 to
docker0. Not required if only 10GE ports are used

-p 8700
Optional. The vPFE's serial console is connected to this port within the container.
Use 'docker ps' to find out the dynamically allocated TCP port on the docker host.

-p 5901
Optional. The vPFE's VNC/video console is connected to this port within the container.
Use 'docker ps' to find out the dynamically allocated TCP port on the docker host.

--v $PWD:/u:ro   
Provides read-only access to vmx tar and config file in the current directory from
within the container. The destination directory must always be /u and the
source directory can be adjusted as needed.

-c <junos config file>
Optional. Specify a config file that is loaded at boot time.

-l <license key file>
Optional. Contains the license key to enable features and bandwidth. Requires
option -i until cloud-init fully support license keys in vMX

-i <ssh/netconf private key file>
Required to install the license key file and to enable services defined via
apply-groups. The config must have the public key stored for user 'snabbvmx'

-v <number of virtual cpus for vPFE, defaults to 3 for vPFE>

-m <memory in kBytes for vPFE, defaults to 8000>

vmx-15.1F3.11.tgz
Filename of the vMX distribution package. Must be available directly in the 
current directory (symbolic links won't work)

<int1> <int2> ... <intN>
Space separated ordered list interface list given to the vMX. Possible
interfaces are physical network interfae names (e.g. eth0, p2p1, etc),
virtual bridges (which will be automatically created) and PCI addresses
of Intel 82599 based 10 Gigabit Ethernet ports. All interface types can
be mixed.

The container is launched in the background. Use 'docker attach <name>' to 
attach to the vMX RE console.

To launch a debugging shell in the running container, use 'docker exec -ti <name> bash'


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







