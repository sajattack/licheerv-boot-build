# -*- GNUMakefile -*-
# Requirements:
#  /bin/bash as SHELL

export SHELL = /bin/bash

all:    world

TOOLCHAIN ?= toolchain

include ${TOOLCHAIN}/target.mak

ifndef TOOLCHAIN_PREFIX
TOOLCHAIN_PREFIX := ${CURDIR}/toolchain/${TARGET_CROSS}
endif

ifndef TARGET_CROSS_PREFIX
TARGET_CROSS_PREFIX = ${TOOLCHAIN_PREFIX}/bin/${TARGET_CROSS}
endif

ifndef PARALLEL
ifndef NOPARALLEL
PARALLEL := -j$(shell echo $$((`nproc` + 2)))
endif
endif

KERNEL_TREE ?= ${CURDIR}/linux
SYSROOT ?= ${CURDIR}/initramfs

export PATH := ${TOOLCHAIN_PREFIX}/bin:${PATH}

${SYSROOT}:
	mkdir -p $@

${SYSROOT}/.mount-stamp:	| ${SYSROOT}
	touch $@

.PHONY: world

world: \
	build-linux/arch/${TARGET_ARCH}/boot/Image \
	u-boot/u-boot.itb \
	${SYSROOT}/lib/modules

# --- toolchain

riscv-gnu-toolchain/Makefile:	riscv-gnu-toolchain
	( cd riscv-gnu-toolchain && \
	./configure \
	--prefix=${TOOLCHAIN_PREFIX} \
	--with-arch=${TARGET_ARCH_AUX2} \
	--with-abi=${TARGET_FLOAT_ABI} )

${TARGET_CROSS_PREFIX}-gcc:	riscv-gnu-toolchain/Makefile
	make ${PARALLEL} -C riscv-gnu-toolchain linux

# --- opensbi

opensbi/build/platform/generic/firmware/fw_dynamic.bin: opensbi ${TARGET_CROSS_PREFIX}-gcc
	make -C opensbi CROSS_COMPILE=${TARGET_CROSS_PREFIX}- PLATFORM=generic

.PHONY: opensbi-build

opensbi-build:	opensbi/build/platform/generic/firmware/fw_dynamic.bin

# --- u-boot

u-boot/.config:	u-boot opensbi/build/platform/generic/firmware/fw_dynamic.bin
	OPENSBI=${CURDIR}/opensbi/build/platform/generic/firmware/fw_dynamic.bin \
	make -C u-boot sifive_hifive_unmatched_fu740_defconfig

u-boot/u-boot.itb:	u-boot/.config
	OPENSBI=${CURDIR}/opensbi/build/platform/generic/firmware/fw_dynamic.bin \
	make ${PARALLEL} -C u-boot ARCH=${TARGET_ARCH} CROSS_COMPILE=${TARGET_CROSS}- all

.PHONY: build-uboot

build-uboot:	u-boot/u-boot.itb

# --- kernel

build-linux/arch/${TARGET_ARCH}/configs:
	mkdir -p $@

.PHONY: kernel

build-linux/arch/${TARGET_ARCH}/configs/hifive_unmatched_defconfig: | build-linux/arch/${TARGET_ARCH}/configs configs/hifive_unmatched_defconfig
	cp configs/hifive_unmatched_defconfig $@

build-linux/.config:   | build-linux/arch/${TARGET_ARCH}/configs/hifive_unmatched_defconfig
	make ARCH=${TARGET_ARCH} -C ${KERNEL_TREE} O=${CURDIR}/build-linux hifive_unmatched_defconfig

build-linux/arch/${TARGET_ARCH}/boot/Image: build-linux/.config ${TARGET_CROSS_PREFIX}-gcc
	make ${PARALLEL} -C build-linux ARCH=${TARGET_ARCH} CROSS_COMPILE=${TARGET_CROSS_PREFIX}- V=1

kernel:	build-linux/arch/${TARGET_ARCH}/boot/Image

.PHONY: .install-modules

${SYSROOT}/lib/modules:	build-linux/arch/${TARGET_ARCH}/boot/Image
	make ${PARALLEL} -C build-linux INSTALL_MOD_PATH=${SYSROOT} modules_install

.install-modules: ${SYSROOT}/lib/modules ${SYSROOT}/.mount-stamp

clean::
	-make ${PARALLEL} -C build-linux clean
	-make ${PARALLEL} -C ${KERNEL_TREE} mrproper
	-rm -rf ${SYSROOT}/lib/modules

distclean::
	-rm -rf build-linux
