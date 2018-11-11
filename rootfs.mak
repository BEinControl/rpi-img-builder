ifdef OVERRIDES
	include $(OVERRIDES)
endif
include common.mk

.PHONY: all
all: build

.PHONY: clean
clean: delete-rootfs
	if mountpoint -q mnt; then \
		umount mnt; \
	fi
	rm -rf $(IMAGE_FILE)*.img *.img.tmp mnt multistrap.list *.example plugins.txt multistrap.err

.PHONY: distclean
distclean: delete-rootfs
	rm -rf $(wildcard $(ROOTFS_DIR).base $(ROOTFS_DIR).base.tmp)

.PHONY: delete-rootfs
delete-rootfs:
	if mountpoint -q $(ROOTFS_DIR)/proc; then \
		umount $(ROOTFS_DIR)/proc; \
	fi
	if mountpoint -q $(ROOTFS_DIR)/sys; then \
		umount $(ROOTFS_DIR)/sys; \
	fi
	if mountpoint -q $(ROOTFS_DIR)/dev; then \
		umount $(ROOTFS_DIR)/dev; \
	fi
	if mountpoint -q $(ROOTFS_DIR)/package-cache-common; then \
		umount $(ROOTFS_DIR)/package-cache-common; \
	fi
	rm -rf $(wildcard $(ROOTFS_DIR) uInitrd)

.PHONY: build
build: $(IMAGE_FILE)

$(ROOTFS_DIR).base:
	if [ "$(QEMUFULL)" = "" ]; then \
		echo "ERROR: $(QEMU) not found."; \
		exit 1; \
	fi

	# Identify Plugins
	rm -f plugins.txt
	echo "Scanning for plugins ..."
	for j in $(REPOS); do \
		for i in plugins/REPO/$$j/*; do \
			if [ -f $$i/baseonly -a $$j != $(REPOBASE) ]; then \
				continue; \
			fi; \
			if [ -f $$i/disabled ]; then \
				echo " - Skipping disabled REPO plugin: $$(basename $$j)/$$(basename $$i)"; \
				continue; \
			fi; \
			echo $$(realpath $$i) >> plugins.txt; \
		done; \
	done
	for i in plugins/DIST/$(DIST)/*; do \
		if [ -f $$i/disabled ]; then \
			echo " - Skipping disabled DIST plugin: $$(basename $$i)"; \
			continue; \
		fi; \
		echo $$(realpath $$i) >> plugins.txt; \
	done
	for i in plugins/COMMON/*; do \
		if [ -f $$i/disabled ]; then \
			echo " - Skipping disabled COMMON plugin: $$(basename $$i)"; \
			continue; \
		fi; \
		echo $$(realpath $$i) >> plugins.txt; \
	done
	for j in $(PLUGINS_DIR); do \
		for i in $$j/*; do \
			if [ -f $$i/disabled ]; then \
				echo " - Skipping disabled DEVICE plugin: $$(basename $$i)"; \
				continue; \
			fi; \
			echo $$(realpath $$i) >> plugins.txt; \
		done; \
	done

	@echo
	@echo "Building $(IMAGE_FILE)_$(TIMESTAMP).img"
	@echo "Repositories: $(REPOS)"
	@echo "Base repositories: $(REPOBASE)"
	@echo "Distribution: $(DIST)"
	@echo "Repository architecture: $(DARCH)"
	@echo "System architecture: $(ARCH)"
	@echo "Plugins: $$(cat plugins.txt)"
	@echo

	#@echo -n "5..."
	#@sleep 1
	#@echo -n "4..."
	#@sleep 1
	@echo -n "3..."
	@sleep 1
	@echo -n "2..."
	@sleep 1
	@echo -n "1..."
	@sleep 1
	@echo "OK"

	if test -d "$@.tmp"; then \
		rm -rf "$@.tmp"; \
	fi

	mkdir -p $@.tmp/etc/apt/apt.conf.d
	# Leave atp.conf in place for postinstall, who will remove it before building final image
	cp apt.conf $@.tmp/etc/apt/apt.conf.d/00rpi-img-builder

	# Build multistrap
	cat $(shell echo multistrap.list.in; for i in $(REPOS); do echo repos/$$i/multistrap.list.in; done | xargs) | sed -e 's,__REPOSITORIES__,$(REPOS),g' -e 's,__SUITE__,$(DIST),g' -e 's,__FSUITE__,$(FDIST),g' -e 's,__ARCH__,$(ARCH),g' > multistrap.list
	multistrap --arch $(DARCH) --file multistrap.list --dir $@.tmp 2>multistrap.err || true
	if [ -f multistrap.err ]; then \
		if grep -q '^E' multistrap.err; then \
			echo; \
			echo; \
			echo "::: Something went wrong please review multistrap.err to figure out what."; \
			echo; \
			echo =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=; \
			cat multistrap.err; \
			echo =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=; \
			echo; \
			exit 1; \
		fi; \
	fi

	cp $(QEMUFULL) $@.tmp/usr/bin

	mkdir -p $@.tmp/usr/share/fatboothack/overlays

	if test ! -f $@.tmp/etc/resolv.conf; then \
		cp /etc/resolv.conf $@.tmp/etc/; \
	fi

	# No idea why multistrap does this
	# DFARRELL - Wrapped this around the arch64 check
	if [ "$(DARCH)" != "arm64" ]; then \
		rm -f $@.tmp/lib64; \
	fi

	ln -s /proc/mounts $@.tmp/etc/mtab

	mv $@.tmp $@

	touch $@

$(ROOTFS_DIR): $(ROOTFS_DIR).base
	rsync --quiet --archive --devices --specials --hard-links --acls --xattrs --sparse $(ROOTFS_DIR).base/* $@

	touch $@/packages.txt

	mkdir -p $@/package-cache-common
	mkdir -p $@/package-cache-plugins

	mkdir $@/postinst
	mkdir $@/postinst-files
	mkdir $@/apt-keys

	# Process plugin files
	for i in $$(cat plugins.txt | xargs); do \
		echo "Processing plugin $$i..."; \
		if [ -d $$i/files ]; then \
			echo " - found pre-install files ... adding"; \
			cd $$i/files && find . -type f ! -name '*~' -exec cp --preserve=mode,timestamps --parents \{\} $@ \;; \
			cd $(BASE_DIR); \
		fi; \
		if [ -d $$i/preinst-files ]; then \
			echo " - found pre-install files ... adding"; \
			cd $$i/preinst-files && find . -type f ! -name '*~' -exec cp --preserve=mode,timestamps --parents \{\} $@ \;; \
			cd $(BASE_DIR); \
		fi; \
		if [ -f $$i/packages ]; then \
			echo " - found packages ... adding"; \
			echo -n "$$(cat $$i/packages | sed -e "s,__ARCH__,$(ARCH),g" | xargs) " >> $@/packages.txt; \
		fi; \
		if [ -d $$i/package-cache ]; then \
			echo " - found package cache ... adding"; \
			cd $$i/package-cache && find . -type f ! -name '*~' -exec cp --preserve=mode,timestamps --parents \{\} $@/package-cache-plugins \;; \
			cd $(BASE_DIR); \
		fi; \
		if [ -d $$i/postinst-files ]; then \
			echo " - found post-install files ... adding"; \
			cd $$i/postinst-files && find . -type f ! -name '*~' -exec cp --preserve=mode,timestamps --parents \{\} $@/postinst-files \;; \
			cd $(BASE_DIR); \
		fi; \
		if [ -f $$i/preinst ]; then \
			echo " - found pre-install script ... running"; \
			# DFARRELL - Try sourcing the file to avoid having to chmod it, which can fail on r/o systems. \
			# chmod +x $$i/preinst; \
			. $$i/preinst || exit 1; \
		fi; \
		if [ -f $$i/postinst ]; then \
			echo " - found post-install script ... adding"; \
			cp $$i/postinst $@/postinst/$$(dirname $$i/postinst | rev | cut -d/ -f1 | rev)-$$(cat /dev/urandom | LC_CTYPE=C tr -dc "a-zA-Z0-9" | head -c 5); \
		fi; \
	done

	# Fix permissions on tmp, if need-be
	if [ "`stat -c %a $@/tmp`" != "1777" ]; then \
	        echo "Fixing permissions on $@/tmp" ; \
	        chmod a+rwx,+t $@/tmp ; \
	        if [ "`stat -c %a $@/tmp`" != "1777" ]; then \
	                echo "$@/tmp folder has incorrect permissions: `stat -c %a $@/tmp`" ; \
	                exit 1 ;\
	        fi ; \
	fi

	# Make postinst scripts executable
	chmod +x $@/postinst/*

	# Add chroot mount points
	echo "Adding mount points"
	mount -o bind /proc $@/proc
	mount -o bind /sys  $@/sys
	mount -o bind /dev  $@/dev

	# Mount common package dir, if present
	if [ ! -z "$(PKG_CACHE_DIR)" -a -d "$(PKG_CACHE_DIR)" ]; then \
		echo "Mounting package-cache directory: '$(PKG_CACHE_DIR)'" ; \
		mount --bind "$(PKG_CACHE_DIR)" $@/package-cache-common ; \
	fi
	# DFARRELL - Alternative to mounting (disabled)
	# Copy debs from common package dir to working dir
	#if [ ! -z "$(PKG_CACHE_DIR)" -a -d "$(PKG_CACHE_DIR)" ]; then \
	#	cd "$(PKG_CACHE_DIR)"; \
	#	find . -type f -name '*.deb' -exec cp --parents \{\} $@/package-cache-common \;; \
	#	cd $(BASE_DIR); \
	#fi

	# Run postinstall script within chroot
	cp postinstall $@
	chroot $@ /bin/bash -c "/postinstall $(DIST) $(ARCH) $(LOCALE) $(TZONE) $(UNAME) '$(UPASS)' '$(RPASS)' $(INC_REC) $(UBOOT_DIR)"

	# Apply patches
	for i in $$(cat plugins.txt | xargs); do \
		if [ -d $$i/patches ]; then \
			for j in $$i/patches/*; do \
				patch -p0 -d $@ < $$j; \
			done; \
		fi; \
	done

	# DFARRELL - Added "\n" to echo to ensure property is on a new line (untested)
	if [ -f $@/$(BOOT_DIR)/config.txt -a "$(DARCH)" = "arm64" ]; then \
		if ! grep "arm_64bit=1" $@/$(BOOT_DIR)/config.txt > /dev/null; then \
			echo "\narm_64bit=1" >> $@/$(BOOT_DIR)/config.txt; \
		fi; \
	fi

	# TODO DFARRELL - Is this needed?
	mkdir -p $@/lib/firmware/brcm
	cp brcmfmac43430-sdio.txt $@/lib/firmware/brcm/

	# Remove working files/dirs
	rm -f $@/packages.txt
	rm -f $@/postinstall

	rm -rf $@/package-cache-plugins
	rm -rf $@/postinst
	rm -rf $@/postinst-files
	rm -rf $@/apt-keys

	rm -f $@/usr/bin/$(QEMU)
	rm -f $@/etc/resolv.conf

	# Unmount common package dir, if mounted
	if mountpoint -q $@/package-cache-common ; then \
		echo "Unmounting package-cache directory" ; \
		umount $@/package-cache-common ; \
	fi
	rmdir $@/package-cache-common
	# Remove chroot mount points
	# NOTE: Make these the LAST umounts
	echo "Removing chroot mount points"
	umount $@/proc
	umount $@/sys
	umount $@/dev

	touch $@

$(IMAGE_FILE): $(ROOTFS_DIR)
	if test -f "$@.img.tmp"; then \
		rm -f "$@.img.tmp"; \
	fi

	./createimg $@.img.tmp $(BOOT_MB) $(ROOT_MB) $(BOOT_DIR) $(ROOTFS_DIR) "$(ROOT_DEV)"

	mv $@.img.tmp $@_$(TIMESTAMP).img

	@echo
	@echo "Built $(IMAGE_FILE)_$(TIMESTAMP).img"
	@echo "Repositories: $(REPOS)"
	@echo "Base repositories: $(REPOBASE)"
	@echo "Distribution: $(DIST)"
	@echo "Repository architecture: $(DARCH)"
	@echo "System architecture: $(ARCH)"
	@echo "Plugins: $$(cat plugins.txt)"
	@echo

	touch $@_$(TIMESTAMP).img
