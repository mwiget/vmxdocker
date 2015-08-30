FROM ubuntu:14.04
MAINTAINER Marcel Wiget

# Install enough packages to compile snabb and qemu
RUN apt-get update
RUN apt-get install -y build-essential gcc pkg-config glib-2.0 libglib2.0-dev libsdl1.2-dev libaio-dev libcap-dev libattr1-dev libpixman-1-dev libncurses5 libncurses5-dev git telnet tmux numactl bc debootstrap bridge-utils

# Download and compile qemu. Official build doesn't support reconnects, so
# we use the one from snabb for now
#RUN git clone git://git.qemu-project.org/qemu.git
RUN git clone -b v2.1.0-vhostuser --depth 50 https://github.com/SnabbCo/qemu && \
	cd qemu && ./configure --target-list=x86_64-softmmu && make -j

# Download and compile Snabb Switch
# RUN git clone https://github.com/SnabbCo/snabbswitch && cd snabbswitch && make
RUN git clone https://github.com/mwiget/snabbswitch.git && cd snabbswitch && make

ENV VCP jinstall64-vmx-14.1R5.4-domestic.img
ENV VFP vPFE-lite-20150707.img
ENV HDD vmxhdd.img

COPY ${VFP} ${VCP} ${HDD} /

# rename the image files to default values used to launch via qemu
RUN mv ${VFP} vfp.img && mv ${VCP} vcp.img && mv ${HDD} hdd.img

COPY launch.sh /

ENTRYPOINT ["/launch.sh"]

CMD ["vmx"]

