include $(TOPDIR)/rules.mk

PKG_NAME:=blue-merle
PKG_VERSION:=3.0.0
PKG_RELEASE:=$(AUTORELEASE)

PKG_MAINTAINER:=Matthias <matthias@srlabs.de>
PKG_LICENSE:=BSD-3-Clause

include $(INCLUDE_DIR)/package.mk

define Package/blue-merle
	SECTION:=utils
	CATEGORY:=Utilities
	EXTRA_DEPENDS:=luci-base, gl-sdk4-mcu, coreutils-shred, python3
	TITLE:=Anonymity Enhancements for GL.iNet Mudi 7 (GL-E5800)
endef

define Package/blue-merle/description
	The blue-merle package enhances anonymity and reduces forensic traceability of
	the GL.iNet Mudi 7 (GL-E5800) 5G mobile router. It targets the Qualcomm
	Snapdragon X72 (Dragonwing MBB Gen 3) modem and supports the device's dual
	nano-SIM configuration.
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/blue-merle/install
	$(CP) ./files/* $(1)/
	$(INSTALL_BIN) ./files/etc/init.d/* $(1)/etc/init.d/
	$(INSTALL_BIN) ./files/etc/gl-switch.d/* $(1)/etc/gl-switch.d/
	$(INSTALL_BIN) ./files/usr/bin/* $(1)/usr/bin/
	$(INSTALL_BIN) ./files/usr/libexec/blue-merle $(1)/usr/libexec/blue-merle
	$(INSTALL_BIN) ./files/lib/blue-merle/imei_generate.py  $(1)/lib/blue-merle/imei_generate.py
endef

define Package/blue-merle/preinst
	#!/bin/sh
	[ -n "$${IPKG_INSTROOT}" ] && exit 0	# if run within buildroot exit

	ABORT_GLVERSION () {
		echo
		if [ -f "/tmp/sysinfo/model" ] && [ -f "/etc/glversion" ]; then
			echo "You have a `cat /tmp/sysinfo/model`, running firmware version `cat /etc/glversion`."
		fi
		echo "blue-merle 3.x targets the GL.iNet Mudi 7 (GL-E5800) running gl-sdk4-based firmware."
		echo "The device or firmware version you are using has not been verified to work with blue-merle."
		echo -n "Would you like to continue at your own risk? (y/N): "
		read answer
		case $$answer in
				y*) answer=0;;
				Y*) answer=0;;
				*) answer=1;;
		esac
		if [[ "$$answer" -eq 0 ]]; then
			exit 0
		else
			exit 1
		fi
	}

	# /proc/cpuinfo on aarch64 doesn't carry the GL.iNet model string,
	# so prefer /tmp/sysinfo/model which OpenWrt populates from DT.
	MODEL_FILE=/tmp/sysinfo/model
	if [ ! -r "$$MODEL_FILE" ]; then
		MODEL_FILE=/proc/cpuinfo
	fi

	if grep -q -E "GL-E5800|Mudi[ -]?7" "$$MODEL_FILE"; then
		GL_VERSION=$$(cat /etc/glversion 2>/dev/null || echo unknown)
		case $$GL_VERSION in
		    4.7.*|4.8.*|4.9.*|5.*)
		        echo Firmware version $$GL_VERSION is supported
		        ;;
		    *)
		        echo Unverified firmware version $$GL_VERSION
		        ABORT_GLVERSION
		        ;;
		esac
	else
		ABORT_GLVERSION
	fi

	# Our volatile-mac service gets started during the installation
	# but it modifies the client database held by the gl_clients process.
	# So we stop that process now, have the database put onto volatile storage
	# and start the service after installation.
	/etc/init.d/gl_clients stop 2>/dev/null
endef

define Package/blue-merle/postinst
	#!/bin/sh
	uci set switch-button.@main[0].func='sim' 2>/dev/null
	uci commit switch-button 2>/dev/null

	/etc/init.d/gl_clients start 2>/dev/null

	echo {\"msg\": \"Successfully installed Blue Merle\"} > /dev/ttyS0 2>/dev/null
endef

define Package/blue-merle/postrm
	#!/bin/sh
	uci set switch-button.@main[0].func='tor' 2>/dev/null
	uci commit switch-button 2>/dev/null
endef
$(eval $(call BuildPackage,$(PKG_NAME)))
