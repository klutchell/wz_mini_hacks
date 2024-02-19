
ifneq ($(ENV),)
	include .env.$(ENV)
endif

GITHUB_USER ?=
CUSTOM_HOSTNAME ?= WCV3
DEVICE ?= /dev/diskN
VOLUME_NAME ?= WZ_MINI
VOLUME_MOUNT ?= /Volumes/$(VOLUME_NAME)

FIRMWARE_ZIP ?= ./demo_wcv3_4.36.9.139.zip

# Convert 100GB to bytes for comparison
MAX_SIZE_BYTES ?= $(shell echo $$((100 * 1024 * 1024 * 1024)))

ifneq ($(DEVICE),/dev/diskN)
# Check if the device is removable
REMOVABLE := $(shell diskutil info $(DEVICE) | awk ' /Removable Media/ {print $$3}')
# Get the device size in bytes
DEVICE_SIZE_BYTES := $(shell diskutil info $(DEVICE) | awk -F '[()]' '/Disk Size/ {print $$2}' | awk '{print $$1}')
endif

check-ip:
ifeq ($(IP),)
	$(error IP is not set)
endif

check-device:
ifeq ($(DEVICE),)
	$(error DEVICE is not set)
endif
ifeq ($(DEVICE),/dev/diskN)
	$(error DEVICE is not set to a valid device)
endif
ifneq ($(REMOVABLE),Removable)
	$(error DEVICE is not removable)
endif
	@[[ "$(DEVICE_SIZE_BYTES)" -lt "$(MAX_SIZE_BYTES)" ]] || exit 1

keys:
ifeq ($(GITHUB_USER),)
	$(error GITHUB_USER is not set)
endif
	curl https://github.com/$(GITHUB_USER).keys > ./SD_ROOT/wz_mini/etc/ssh/authorized_keys

forget-host: check-ip
	ssh-keygen -R $(IP)

ssh: check-ip
	ssh root@$(IP)

go2rtc: check-ip
	open http://$(IP):1984

patch:
	git apply --ignore-whitespace ./patches/*.patch

sync: check-ip set-hostname
	rsync -v --progress SD_ROOT/wz_mini/ "root@$(IP):/media/mmc/wz_mini/"
	ssh "root@$(IP)" "reboot"

set-hostname:
ifeq ($(CUSTOM_HOSTNAME),)
	$(error CUSTOM_HOSTNAME is not set)
endif
	sed "s/^CUSTOM_HOSTNAME=.*/CUSTOM_HOSTNAME=\"$(CUSTOM_HOSTNAME)\"/" -i SD_ROOT/wz_mini/wz_mini.conf

unmount: check-device
	diskutil unmountDisk $(DEVICE)

mount: check-device
	diskutil mount $(VOLUME_MOUNT)

format: check-device unmount
	diskutil eraseDisk FAT32 $(VOLUME_NAME) MBRFormat $(DEVICE)

write: keys set-hostname format mount
	rsync -av --progress --exclude .Spotlight-V100 SD_ROOT/ $(VOLUME_MOUNT)/ --delete
	$(MAKE) unmount

firmware: format mount
	unzip -o $(FIRMWARE_ZIP) -d $(VOLUME_MOUNT)
	$(MAKE) unmount

clean: ENV :=
clean: set-hostname
	git checkout ./SD_ROOT/wz_mini/wz_mini.conf
	git checkout ./SD_ROOT/wz_mini/etc/ssh/authorized_keys

.PHONY: keys sync forget-host ssh go2rtc set-hostname unmount mount format write check-device check-ip firmware clean
