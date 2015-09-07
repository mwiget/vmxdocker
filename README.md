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

### Running 
### Building the vMX Docker Image

- Clone this repository to the linux server

	```
	git clone https://github.com/mwiget/vmxdocker.git
	cd vmxdocker
	```
	
- Download the latest vMX package from [http://www.juniper.net/support/downloads/?p=vmx#sw](http://www.juniper.net/support/downloads/?p=vmx#sw)
- Extract the .img files from the tar file and copy them to the folder vmxdocker folder:

	```
	tar zxf vmx-14.1R5.4-1.tgz
	cp vmx-14.1R5.4-1/images/*img .
	rm -rf vmx-14.1R5.4-1
	```
	
- Building the image

	Check the content of the dockerfile if the filenames for the vMX .img files are still correct. They are currently set to use 14.1R5.4 and the lite version of the vPFE. Then build the image. You can pick any repository name tag that fits. It will download qemu and compile it. Same for Snabb, currently downloaded from a non-authoritative fork containing pull request [#604](https://github.com/SnabbCo/snabbswitch/pull/604) that allows all ethernet frames to be received on the wire and delivered to the vMX. 
	
	```
	docker build -t marcelwiget/vmx:14.1R5.4-lite .
	```
	
	The vmx image is now available for launch:
	
	```
	docker images marcelwiget/vmx
REPOSITORY          TAG                 IMAGE ID            CREATED             VIRTUAL SIZE
marcelwiget/vmx     14.1R5.4-lite       c521e20991f5        9 hours ago         2.781 GB
```

### Launching vMX Container

Find the PCI address(es) of the 10G ports:

```
lspci|grep 10-
04:00.0 Ethernet controller: Intel Corporation 82599ES 10-Gigabit SFI/SFP+ Network Connection (rev 01)
04:00.1 Ethernet controller: Intel Corporation 82599ES 10-Gigabit SFI/SFP+ Network Connection (rev 01)
```

This system has a single Intel 10G card with 2 ports, available at PCI addresses 0000:04:00.0 and 0000:04:00.1. They must be passed via environment variable to the docker run command. In this example, a single 10G port is given to the vMX. Multiple ports can be passed by listing all PCI addresses, separated by white space.

```
docker run --name vmx --rm --privileged --env PCIDEVS=0000:04:00.1 -i -t marcelwiget/vmx:14.1R5.4-lite
```

This will launch vMX in an interactive terminal session with tmux and the routing engine in the active tmux window. See launch.sh for details. Once the routing engine has booted successfully, log in as user root, no password and configure the ge-0/0/0 router port. The fxp0 management port is only attached to an internal bridge within the container and hence not really useable without change.

IMPORTANT: Don't detach from tmux with tmux detach option but rather detach from the interactive Docker session via ^P^Q. See [http://docs.docker.com/articles/basics/](http://docs.docker.com/articles/basics/) for details. 

		






