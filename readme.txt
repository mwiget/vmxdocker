Juniper Networks vMX Docker Container 

Requirements:

- vmx Container marcelwiget/vmx. 
- Juniper Networks vMX distribution tar file. E.g. vmx-14.1R5.4-1.tgz
  (download from http://www.juniper.net/support/downloads/?p=vmx#sw, valid user account required).
- Bare metal server with docker engine installed

Usage:

$ docker run --name vmx1 --rm --privileged --net=host \
  -v $PWD:/u:ro \
  --env TAR="vmx-14.1R5.4-1.tgz" \
  --env CFG="vmx1.cfg" \
  --env DEV="br0 br0" \
  --env PFE="lite" \
  --env MEM="5000" --env VCPU="5" \
  -i -t marcelwiget/vmx:latest

--name <name> The name must be unique across containers on the same server (e.g. vmx1)

--rm          Destroy the container after termination (use -d to run as daemon instead)

-d            Optional instead of --rm: Launch the Container in detached mode, making
              it possible to launch vMX fully unattended, while allowing the user to
              re-attach to the console via 'docker attach <name>'.

--privileged  Required to allow creation of virtual bridges and tap interfaces and
              mounting of hugetables as a filesystem

--net=host    Required to allow interface and virtual bridge access across containers and
              between the host and containers. It also allows the binding of fxp0 to 
              docker0 (--net is optional when using 10GE ports only and fxp0 isn't required)

--v $PWD:/u   Provides access to vmx tar and config file in the current directory from 
              within the container. The destination directory must always be /u and the 
              source directory can be adjusted as needed.

--env TAR     Specify the filename of the vMX distribution tar file provided in /u to
              the container (see --v option)

--env CFG     Optional. Specify a config file that allows zero-touch provisioning of
              the vMX. See an example further down. It is possible to set a license key
              as well, but large configs should be transferred via netconf/ssh, because
              the content of the file is sent to the virtual serial based console with
              a 1 sec delay after each line.

--env DEV     Space separated ordered list interface list given to the vMX. Possible
              interfaces are physical network interfae names (e.g. eth0, p2p1, etc),
              virtual bridges (which will be automatically created) and PCI addresses
              of Intel 82599 based 10 Gigabit Ethernet ports. All interface types can
              be mixed.

--env VCP    Optional. Specify a virtual disk image for the VCP/vRE instead of taking it
             from the TAR file. 

--env PFE    Optional. If set to "lite", the lite version of the vPFE is used, even if
             the CPU would allow the use of the high performance vPFE image from the 
             provided vMX distribution tar file.

--env MEM    Optional. Set the amount of memory in MB given to the vPFE image. 
             default is 5000. The vRE image is hard set in launch.sh to 2000MB.

--env VCPU  Optional. Set the number of vCPU to be used by the vPFE. Default is 5.
            The vRE image is hard set in launch.sh to 1 vCPU.

-i          Keep STDIN open even if not attached. Required to keep tmux happy, even when
            not attached.

-t          Allocate a pseudo-TTY. Required for proper operation.


Examples:

Launch 2 vMX containers named vmx1 and vmx2 with configs vmx1.cfg and vmx2.cfg and connect
them via a virtual bridge br0 (which will be automatically created and destroyed as needed):

  Router config files:

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

  Attach to either vmx via 

  $ docker attach vmx1

  It is also possible to launch the container directly in interactive mode, so
  progress can be monitored and the router console is accessible:

  docker run --name vmx1 --rm --privileged --net=host \
    -v $PWD:/u:ro \
    --env TAR="vmx-14.1R5.4-1.tgz" \
    --env CFG="vmx1.cfg" \
    --env DEV="br0" \
    --env PFE="lite" \
    --env MEM="5000" --env VCPU="5" \
    -i -t marcelwiget/vmx:latest


Example of a single router connecting to 2 10GE ports:

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

  docker run --name vmx3 --rm --privileged --net=host \
    -v $PWD:/u:ro \
    --env TAR="vmx-14.1R5.4-1.tgz" \
    --env CFG="vmx3.cfg" \
    --env DEV="0000:04:00.0 0000:04:00.1" \
    --env PFE="lite" \
    --env MEM="5000" --env VCPU="5" \
    -i -t marcelwiget/vmx:latest


IMPORTANT: Instead of detaching from tmux via ^BD, use docker's method of detaching
from an interactive docker session via ^P^Q. Failing to do so will kill the vMX and
the virtual interfaces and bridges will be cleaned up.



Copyright 2015 Juniper Networks Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

