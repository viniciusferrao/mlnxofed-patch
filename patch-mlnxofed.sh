#!/bin/sh
# Patch to add back support for MLX4 and EFA on MLNX OFED
# This script is only tested against Enterprise Linux 8
#
# vinicius {\a\t} ferrao.net.br
# ferrao {\a\t} versatushpc.com.br

# Stop execution in case of any error (add x for debugging)
set -e

# Output directory for the new RPMS
RPMS_OUTPUT_DIR=$HOME/PATCHED-MLNX-OFED
# rpmbuild root directory
RPM_BUILD_ROOT=~/dd90dbfa-8d9f-43dd-a7ac-89f73e80e40f
# Work directory to patch the files
WORK_DIR=~/0995edb8-df4b-49f0-a144-fc6fa8835b71

# perl is being too verbose without hardcoding locales
LC_ALL=en_US.UTF-8
LC_CTYPE=en_US.UTF-8

# Patches
patch_mlnx_ofed55() {
# CMakeLists.txt
cat > CMakeLists.txt.patch << 'EOF'
--- CMakeLists.txt		2021-11-16 12:47:39.000000000 -0300
+++ CMakeLists.txt.patched	2022-02-08 00:19:07.699078760 -0300
@@ -674,13 +674,15 @@
 if (0)
 add_subdirectory(providers/bnxt_re)
 add_subdirectory(providers/cxgb4) # NO SPARSE
+endif()
 add_subdirectory(providers/efa)
 add_subdirectory(providers/efa/man)
+if (0)
 add_subdirectory(providers/hns)
 add_subdirectory(providers/irdma)
+endif()
 add_subdirectory(providers/mlx4)
 add_subdirectory(providers/mlx4/man)
-endif()
 add_subdirectory(providers/mlx5)
 add_subdirectory(providers/mlx5/man)
 if (0)
EOF

patch -u CMakeLists.txt -i CMakeLists.txt.patch
rm -f CMakeLists.txt.patch
echo Patched: CMakeLists.txt
echo

# providers/mlx4/CMakeLists.txt
cat > CMakeLists.txt.patch << 'EOF'
--- CMakeLists.txt		2021-11-16 12:47:39.000000000 -0300
+++ CMakeLists.txt.patched	2022-02-08 00:46:16.715476920 -0300
@@ -13,8 +13,6 @@
   mlx4dv.h
 )
 
-if (0)
 install(FILES "mlx4.conf" DESTINATION "${CMAKE_INSTALL_SYSCONFDIR}/modprobe.d/")
-endif()
 
 rdma_pkg_config("mlx4" "libibverbs" "${CMAKE_THREAD_LIBS_INIT}")
EOF

patch -u providers/mlx4/CMakeLists.txt -i CMakeLists.txt.patch
rm -f CMakeLists.txt.patch
echo Patched: providers/mlx4/CMakeLists.txt
echo

# pyverbs/CMakeLists.txt
cat > CMakeLists.txt.patch << 'EOF'
--- CMakeLists.txt		2021-11-16 12:47:39.000000000 -0300
+++ CMakeLists.txt.patched	2022-02-08 00:17:22.662412580 -0300
@@ -50,7 +50,5 @@
 # mlx5 and efa providers are not built without coherent DMA, e.g. ARM32 build.
 if (HAVE_COHERENT_DMA)
 add_subdirectory(providers/mlx5)
-if (0)
 add_subdirectory(providers/efa)
 endif()
-endif()
EOF

patch -u pyverbs/CMakeLists.txt -i CMakeLists.txt.patch
rm -f CMakeLists.txt.patch
echo Patched: pyverbs/CMakeLists.txt
echo

# rdma-core.spec
cat > rdma-core.spec.patch << 'EOF'
--- rdma-core.spec		2021-11-16 12:47:39.000000000 -0300
+++ rdma-core.spec.patched	2022-02-08 00:39:25.862231222 -0300
@@ -250,6 +250,8 @@
 Device-specific plug-in ibverbs userspace drivers are included:

 - libirdma: Intel Ethernet Connection RDMA
+- libefa: Amazon Elastic Fabric Adapter
+- libmlx4: Mellanox ConnectX-3 InfiniBand HCA
 - libmlx5: Mellanox ConnectX-4+ InfiniBand HCA

 %package -n libibverbs-utils
@@ -475,9 +477,9 @@
 %doc installed_docs/tag_matching.md
 %config(noreplace) %{_sysconfdir}/rdma/mlx4.conf
 %config(noreplace) %{_sysconfdir}/rdma/modules/rdma.conf
-%if 0
 %dir %{_sysconfdir}/modprobe.d
 %config(noreplace) %{_sysconfdir}/modprobe.d/mlx4.conf
+%if 0
 %config(noreplace) %{_sysconfdir}/modprobe.d/truescale.conf
 %endif
 %dir %{dracutlibdir}
@@ -515,16 +517,20 @@
 %endif
 %{_libdir}/lib*.so
 %{_libdir}/pkgconfig/*.pc
+%{_mandir}/man3/efadv*
 %{_mandir}/man3/ibv_*
 %{_mandir}/man3/rdma*
 %{_mandir}/man3/umad*
 %{_mandir}/man3/*_to_ibv_rate.*
+%{_mandir}/man7/efadv*
 %{_mandir}/man7/rdma_cm.*
 %ifnarch s390x s390
 %{_mandir}/man3/mlx5dv*
+%{_mandir}/man3/mlx4dv*
 %endif
 %ifnarch s390x s390
 %{_mandir}/man7/mlx5dv*
+%{_mandir}/man7/mlx4dv*
 %endif
 %{_mandir}/man3/ibnd_*

@@ -611,10 +617,12 @@
 %files -n libibverbs
 %dir %{_sysconfdir}/libibverbs.d
 %dir %{_libdir}/libibverbs
+%{_libdir}/libefa.so.*
 %{_libdir}/libibverbs*.so.*
 %{_libdir}/libibverbs/*.so
 %ifnarch s390x s390
 %{_libdir}/libmlx5.so.*
+%{_libdir}/libmlx4.so.*
 %endif
 %config(noreplace) %{_sysconfdir}/libibverbs.d/*.driver
 %doc installed_docs/libibverbs.md
EOF

patch -u rdma-core.spec -i rdma-core.spec.patch
rm -f rdma-core.spec.patch
echo Patched: rdma-core.spec
echo
}

patch_mlnx_ofed54() {
# CMakeLists.txt
cat > CMakeLists.txt.patch << 'EOF'
--- CMakeLists.txt		2021-06-24 14:52:47.000000000 -0300
+++ CMakeLists.txt.patched	2022-02-08 01:28:53.495956917 -0300
@@ -675,13 +675,15 @@
 if (0)
 add_subdirectory(providers/bnxt_re)
 add_subdirectory(providers/cxgb4) # NO SPARSE
+endif()
 add_subdirectory(providers/efa)
 add_subdirectory(providers/efa/man)
+if (0)
 add_subdirectory(providers/hns)
 add_subdirectory(providers/i40iw) # NO SPARSE
+endif()
 add_subdirectory(providers/mlx4)
 add_subdirectory(providers/mlx4/man)
-endif()
 add_subdirectory(providers/mlx5)
 add_subdirectory(providers/mlx5/man)
 if (0)
EOF

patch -u CMakeLists.txt -i CMakeLists.txt.patch
rm -f CMakeLists.txt.patch
echo Patched: CMakeLists.txt
echo

# providers/mlx4/CMakeLists.txt
cat > CMakeLists.txt.patch << 'EOF'
--- CMakeLists.txt	2021-06-24 14:52:48.000000000 -0300
+++ CMakeLists.patched	2022-02-08 01:30:59.191535699 -0300
@@ -13,8 +13,6 @@
   mlx4dv.h
 )

-if (0)
 install(FILES "mlx4.conf" DESTINATION "${CMAKE_INSTALL_SYSCONFDIR}/modprobe.d/")
-endif()

 rdma_pkg_config("mlx4" "libibverbs" "${CMAKE_THREAD_LIBS_INIT}")
EOF

patch -u providers/mlx4/CMakeLists.txt -i CMakeLists.txt.patch
rm -f CMakeLists.txt.patch
echo Patched: providers/mlx4/CMakeLists.txt
echo

# pyverbs/CMakeLists.txt
cat > CMakeLists.txt.patch << 'EOF'
--- CMakeLists.txt		2021-06-24 14:52:48.000000000 -0300
+++ CMakeLists.txt.patched	2022-02-08 01:32:32.705686167 -0300
@@ -42,7 +42,5 @@
 # mlx5 and efa providers are not built without coherent DMA, e.g. ARM32 build.
 if (HAVE_COHERENT_DMA)
 add_subdirectory(providers/mlx5)
-if (0)
 add_subdirectory(providers/efa)
 endif()
-endif()
EOF

patch -u pyverbs/CMakeLists.txt -i CMakeLists.txt.patch
rm -f CMakeLists.txt.patch
echo Patched: pyverbs/CMakeLists.txt
echo

# rdma-core.spec
cat > rdma-core.spec.patch << 'EOF'
--- rdma-core.spec		2021-06-24 14:52:48.000000000 -0300
+++ rdma-core.spec.patched	2022-02-08 01:39:22.703883240 -0300
@@ -238,6 +238,8 @@

 Device-specific plug-in ibverbs userspace drivers are included:

+- libefa: Amazon Elastic Fabric Adapter
+- libmlx4: Mellanox ConnectX-3 InfiniBand HCA
 - libmlx5: Mellanox ConnectX-4+ InfiniBand HCA

 %package -n libibverbs-utils
@@ -463,9 +465,9 @@
 %doc installed_docs/tag_matching.md
 %config(noreplace) %{_sysconfdir}/rdma/mlx4.conf
 %config(noreplace) %{_sysconfdir}/rdma/modules/rdma.conf
-%if 0
 %dir %{_sysconfdir}/modprobe.d
 %config(noreplace) %{_sysconfdir}/modprobe.d/mlx4.conf
+%if 0
 %config(noreplace) %{_sysconfdir}/modprobe.d/truescale.conf
 %endif
 %dir %{dracutlibdir}
@@ -503,16 +505,20 @@
 %endif
 %{_libdir}/lib*.so
 %{_libdir}/pkgconfig/*.pc
+%{_mandir}/man3/efadv*
 %{_mandir}/man3/ibv_*
 %{_mandir}/man3/rdma*
 %{_mandir}/man3/umad*
 %{_mandir}/man3/*_to_ibv_rate.*
+%{_mandir}/man7/efadv*
 %{_mandir}/man7/rdma_cm.*
 %ifnarch s390x s390
 %{_mandir}/man3/mlx5dv*
+%{_mandir}/man3/mlx4dv*
 %endif
 %ifnarch s390x s390
 %{_mandir}/man7/mlx5dv*
+%{_mandir}/man7/mlx4dv*
 %endif
 %{_mandir}/man3/ibnd_*

@@ -599,10 +605,12 @@
 %files -n libibverbs
 %dir %{_sysconfdir}/libibverbs.d
 %dir %{_libdir}/libibverbs
+%{_libdir}/libefa.so.*
 %{_libdir}/libibverbs*.so.*
 %{_libdir}/libibverbs/*.so
 %ifnarch s390x s390
 %{_libdir}/libmlx5.so.*
+%{_libdir}/libmlx4.so.*
 %endif
 %config(noreplace) %{_sysconfdir}/libibverbs.d/*.driver
 %doc installed_docs/libibverbs.md
EOF

patch -u rdma-core.spec -i rdma-core.spec.patch
rm -f rdma-core.spec.patch
echo Patched: rdma-core.spec
echo
}

#
# Shell startup (main) begins here
#

# Detect MLNX OFED release
MLNX_OFED_VERSION=`ofed_info -s | cut -f 2- -d- | cut -f 1 -d:`

if [ -z $MLNX_OFED_VERSION ]; then
	echo Cannot detect MLNX OFED, is it installed?
	exit
else
	echo Detected MLNX OFED release: $MLNX_OFED_VERSION
fi

case $MLNX_OFED_VERSION in
	5.5-1.0.3.2)
		# MLNX OFED 5.5-1.0.3.2 version info
		# https://content.mellanox.com/ofed/MLNX_OFED-5.5-1.0.3.2/MLNX_OFED_SRC-5.5-1.0.3.2.tgz
		RDMA_CORE_VERSION="55mlnx37"
		RDMA_CORE_MINOR_VERSION="1.55103"
		RDMA_CORE_NEW_VERSION="55104.versatushpc"
		;;
	5.4-3.1.0.0)
		# MLNX OFED 5.4-3.1.0.0 version info
		# https://content.mellanox.com/ofed/MLNX_OFED-5.4-3.1.0.0/MLNX_OFED_SRC-5.4-3.1.0.0.tgz
		RDMA_CORE_VERSION="54mlnx1"
		RDMA_CORE_MINOR_VERSION="1.54310"
		RDMA_CORE_NEW_VERSION="54311.versatushpc"
		;;
	5.4-3.0.3.0)
		# MLNX OFED 5.4-3.0.3.0 version info
		# https://content.mellanox.com/ofed/MLNX_OFED-5.4-3.0.3.0/MLNX_OFED_SRC-5.4-3.0.3.0.tgz
		RDMA_CORE_VERSION="54mlnx1"
		RDMA_CORE_MINOR_VERSION="1.54303"
		RDMA_CORE_NEW_VERSION="54304.versatushpc"
		;;
	5.4-1.0.3.0)
		# MLNX OFED 5.4-1.0.3.0 version info
		# https://content.mellanox.com/ofed/MLNX_OFED-5.4-1.0.3.0/MLNX_OFED_SRC-5.4-1.0.3.0.tgz
		RDMA_CORE_VERSION="54mlnx1"
		RDMA_CORE_MINOR_VERSION="1.54103"
		RDMA_CORE_NEW_VERSION="54104.versatushpc"
		;;
	*)
		# Unsupported MLNX OFED release
		echo "Unsupported MLNX OFED release: $MLNX_OFED_VERSION"
		exit
		;;
esac

# Create the directory structure to build the packages
mkdir -p $RPM_BUILD_ROOT/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
mkdir -p $WORK_DIR
cd $WORK_DIR

# Install required packages for building
echo Installing required dependencies...
# Workaround for conflicting Cython from OpenHPC 2.x
if [ `rpm -q python3-Cython-ohpc` ] ; then
	dnf remove -y python3-Cython-ohpc
fi
dnf install -y kernel-rpm-macros pandoc cmake3 systemd-devel python3-devel libnl3-devel python3-Cython
echo

# We can try to save some bandwidth if the SRC file is already in place, probably not...
if [ ! -f MLNX_OFED_SRC-$MLNX_OFED_VERSION.tgz ] ; then
	wget https://content.mellanox.com/ofed/MLNX_OFED-$MLNX_OFED_VERSION/MLNX_OFED_SRC-$MLNX_OFED_VERSION.tgz
fi
echo

tar zxf MLNX_OFED_SRC-$MLNX_OFED_VERSION.tgz
echo Extracting files from SRPMS...
rpm2cpio MLNX_OFED_SRC-$MLNX_OFED_VERSION/SRPMS/rdma-core-$RDMA_CORE_VERSION-$RDMA_CORE_MINOR_VERSION.src.rpm | cpio -i
echo

tar zxf rdma-core-$RDMA_CORE_VERSION.tgz
cd rdma-core-$RDMA_CORE_VERSION

echo Patching MLNX OFED to add back support for MLX4 and EFA...
echo
sleep 1

# This case statement will handle patching for different releases
case $MLNX_OFED_VERSION in
	5.5-1.0.3.2)
		patch_mlnx_ofed55
		;;
	5.4-3.1.0.0|\
	5.4-3.0.3.0|\
	5.4-1.0.3.0)
		patch_mlnx_ofed54
		;;
esac

# Copy specfile to outside of the package
cp -f rdma-core.spec ..
cd ..

# Increase the version number and add the distro tag
sed -i s/Release:.*/Release:\ $RDMA_CORE_NEW_VERSION/g rdma-core.spec
sed -i s/Source:.*/Source:\ rdma-core-%{version}-%{release}.tgz/g rdma-core.spec

tar czf rdma-core-$RDMA_CORE_VERSION-$RDMA_CORE_NEW_VERSION.tgz rdma-core-$RDMA_CORE_VERSION
cp rdma-core-$RDMA_CORE_VERSION-$RDMA_CORE_NEW_VERSION.tgz $RPM_BUILD_ROOT/SOURCES

# Rebuild rdma-core
echo Building RPMS... it may take a while
rpmbuild --nodebuginfo --define "_topdir $RPM_BUILD_ROOT" -ba rdma-core.spec 2>/dev/null >/dev/null

mkdir -p $RPMS_OUTPUT_DIR
mv $RPM_BUILD_ROOT/RPMS/x86_64/* $RPMS_OUTPUT_DIR

# We don't want to install with -y; it's a safety measure
cd $RPMS_OUTPUT_DIR
dnf install *

# Cleanup
rm -rf $WORK_DIR
rm -rf $RPM_BUILD_ROOT

echo
echo Mellanox OFED installation has been patched for EFA \(libefa.so\) and MLX4 support
echo RPM packages are available at $RPMS_OUTPUT_DIR
echo
echo Done
