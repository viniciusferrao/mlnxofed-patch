#!/bin/sh
# Patch to add back support for MLX4 and EFA on MLNX OFED
# This script is tested against Enterprise Linux 8 and 9
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

patch_checked() {
	patch_target=$1
	patch_file=$2

	if ! patch -u "$patch_target" -i "$patch_file"; then
		return 1
	fi
	if [ -f "$patch_target.rej" ]; then
		echo "Patch rejected for $patch_target" >&2
		cat "$patch_target.rej" >&2
		return 1
	fi
}

find_rdma_core_archive() {
	find . -maxdepth 1 \( -name "rdma-core-$RDMA_CORE_VERSION.tgz" -o -name "rdma-core-$RDMA_CORE_VERSION.tar.gz" \) | sed -n '1p'
}

enable_mlx4_modprobe_install() {
	install_dest=$1
	cmake_file=providers/mlx4/CMakeLists.txt
	install_line="install(FILES \"mlx4.conf\" DESTINATION \"$install_dest\")"

	if ! grep -F "$install_line" "$cmake_file" >/dev/null; then
		echo "Missing mlx4 modprobe install line" >&2
		return 1
	fi

	if ! awk -v install_line="$install_line" '
		$0 == "if (0)" {
			if ((getline next_line) <= 0) {
				print
				next
			}
			if (next_line == install_line) {
				print next_line
				if ((getline end_line) > 0 && end_line != "endif()") {
					print end_line
				}
				next
			}
			print
			print next_line
			next
		}
		{ print }
	' "$cmake_file" > "$cmake_file.tmp"; then
		rm -f "$cmake_file.tmp"
		return 1
	fi

	mv "$cmake_file.tmp" "$cmake_file"
}

download_source_bundle() {
	version=$1
	source_bundle_name=MLNX_OFED_SRC-$version.tgz

	if curl -fL "https://linux.mellanox.com/public/repo/mlnx_ofed/$version/$source_bundle_name" -o "$source_bundle_name" 2>/dev/null; then
		return 0
	fi

	curl -fL "https://content.mellanox.com/ofed/MLNX_OFED-$version/$source_bundle_name" -o "$source_bundle_name"
}

dnf_install_args() {
	el_major=$(rpm -E '%{?rhel}')

	if [ "$el_major" = 9 ]; then
		echo "-y --nobest"
	else
		echo "-y"
	fi
}

install_required_dependencies() {
	el_major=$(rpm -E '%{?rhel}')
	cmake_package=
	dnf_args=$(dnf_install_args)

	case "$el_major" in
	8)
		cmake_package=cmake3
		;;
	9)
		cmake_package=cmake
		;;
	*)
		cmake_package=cmake
		;;
	esac

	if ! rpm -q --quiet pandoc 2>/dev/null && ! dnf -q list --available pandoc >/dev/null 2>&1; then
		echo "Unable to find pandoc in enabled repositories" >&2
		echo "On Enterprise Linux 9, enable EPEL before running this script" >&2
		return 1
	fi

	dnf install $dnf_args curl cpio kernel-rpm-macros rpm-build patch pandoc "$cmake_package" systemd-devel python3-devel libnl3-devel python3-Cython perl-generators
}

# Patches
patch_mlnx_ofed56plus() {
# CMakeLists.txt
cat > CMakeLists.txt.patch << 'EOF'
--- CMakeLists.txt		2022-10-18 12:38:59.000000000 -0300
+++ CMakeLists.txt.patched	2023-03-06 17:36:22.118634715 -0300
@@ -695,13 +695,15 @@
 if (HAVE_COHERENT_DMA)
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
EOF

patch_checked CMakeLists.txt CMakeLists.txt.patch || return 1
rm -f CMakeLists.txt.patch
echo Patched: CMakeLists.txt
echo

# providers/mlx4/CMakeLists.txt
enable_mlx4_modprobe_install '${CMAKE_INSTALL_MODPROBEDIR}/' || return 1
echo Patched: providers/mlx4/CMakeLists.txt
echo

# pyverbs/CMakeLists.txt
cat > CMakeLists.txt.patch << 'EOF'
--- CMakeLists.txt		2022-10-18 12:39:00.000000000 -0300
+++ CMakeLists.txt.patched	2023-03-06 17:48:48.929234132 -0300
@@ -51,7 +51,5 @@
 # mlx5 and efa providers are not built without coherent DMA, e.g. ARM32 build.
 if (HAVE_COHERENT_DMA)
 add_subdirectory(providers/mlx5)
-if (0)
 add_subdirectory(providers/efa)
 endif()
-endif()
EOF

patch_checked pyverbs/CMakeLists.txt CMakeLists.txt.patch || return 1
rm -f CMakeLists.txt.patch
echo Patched: pyverbs/CMakeLists.txt
echo

# rdma-core.spec
cat > rdma-core.spec.patch << 'EOF'
--- rdma-core.spec		2022-10-18 12:39:00.000000000 -0300
+++ rdma-core.spec.patched	2023-03-06 17:53:38.182443528 -0300
@@ -254,6 +254,8 @@
 Device-specific plug-in ibverbs userspace drivers are included:

 - libirdma: Intel Ethernet Connection RDMA
+- libefa: Amazon Elastic Fabric Adapter
+- libmlx4: Mellanox ConnectX-3 InfiniBand HCA
 - libmlx5: Mellanox ConnectX-4+ InfiniBand HCA

 %package -n libibverbs-utils
@@ -480,9 +482,9 @@
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
@@ -520,16 +522,20 @@
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

@@ -648,10 +654,12 @@
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

patch_checked rdma-core.spec rdma-core.spec.patch || return 1
rm -f rdma-core.spec.patch
echo Patched: rdma-core.spec
echo
}

patch_mlnx_ofed59() {
# CMakeLists.txt
cat > CMakeLists.txt.patch << 'EOF'
--- CMakeLists.txt		2022-12-29 13:02:19.000000000 -0300
+++ CMakeLists.txt.patched	2026-04-10 02:48:41.000000000 -0300
@@ -717,16 +717,18 @@
 if (0)
 add_subdirectory(providers/bnxt_re)
 add_subdirectory(providers/cxgb4) # NO SPARSE
+endif()
 add_subdirectory(providers/efa)
 add_subdirectory(providers/efa/man)
+if (0)
 add_subdirectory(providers/erdma)
 add_subdirectory(providers/hns)
 add_subdirectory(providers/irdma)
 add_subdirectory(providers/mana)
 add_subdirectory(providers/mana/man)
+endif()
 add_subdirectory(providers/mlx4)
 add_subdirectory(providers/mlx4/man)
-endif()
 add_subdirectory(providers/mlx5)
 add_subdirectory(providers/mlx5/man)
 if (0)
EOF

patch_checked CMakeLists.txt CMakeLists.txt.patch || return 1
rm -f CMakeLists.txt.patch
echo Patched: CMakeLists.txt
echo

# providers/mlx4/CMakeLists.txt
enable_mlx4_modprobe_install '${CMAKE_INSTALL_MODPROBEDIR}/' || return 1
echo Patched: providers/mlx4/CMakeLists.txt
echo

# pyverbs/CMakeLists.txt
cat > CMakeLists.txt.patch << 'EOF'
--- CMakeLists.txt		2022-10-18 12:39:00.000000000 -0300
+++ CMakeLists.txt.patched	2023-03-06 17:48:48.929234132 -0300
@@ -51,7 +51,5 @@
 # mlx5 and efa providers are not built without coherent DMA, e.g. ARM32 build.
 if (HAVE_COHERENT_DMA)
 add_subdirectory(providers/mlx5)
-if (0)
 add_subdirectory(providers/efa)
 endif()
-endif()
EOF

patch_checked pyverbs/CMakeLists.txt CMakeLists.txt.patch || return 1
rm -f CMakeLists.txt.patch
echo Patched: pyverbs/CMakeLists.txt
echo

# rdma-core.spec
cat > rdma-core.spec.patch << 'EOF'
--- rdma-core.spec		2022-12-29 13:02:20.000000000 -0300
+++ rdma-core.spec.patched	2026-04-10 02:48:41.000000000 -0300
@@ -260,8 +260,10 @@
 Device-specific plug-in ibverbs userspace drivers are included:

 - liberdma: Alibaba Elastic RDMA (iWarp) Adapter
+- libefa: Amazon Elastic Fabric Adapter
 - libirdma: Intel Ethernet Connection RDMA
 - libmana: Microsoft Azure Network Adapter
+- libmlx4: Mellanox ConnectX-3 InfiniBand HCA
 - libmlx5: Mellanox ConnectX-4+ InfiniBand HCA

 %package -n libibverbs-utils
@@ -489,9 +491,9 @@
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
@@ -527,15 +529,19 @@
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
+%{_mandir}/man3/mlx4dv*
 %{_mandir}/man3/mlx5dv*
 %endif
 %ifnarch s390x s390
+%{_mandir}/man7/mlx4dv*
 %{_mandir}/man7/mlx5dv*
 %endif
 %{_mandir}/man3/ibnd_*
@@ -655,9 +661,11 @@
 %files -n libibverbs
 %dir %{_sysconfdir}/libibverbs.d
 %dir %{_libdir}/libibverbs
+%{_libdir}/libefa.so.*
 %{_libdir}/libibverbs*.so.*
 %{_libdir}/libibverbs/*.so
 %ifnarch s390x s390
+%{_libdir}/libmlx4.so.*
 %{_libdir}/libmlx5.so.*
 %endif
 %config(noreplace) %{_sysconfdir}/libibverbs.d/*.driver
EOF

patch_checked rdma-core.spec rdma-core.spec.patch || return 1
rm -f rdma-core.spec.patch
	echo Patched: rdma-core.spec
	echo
}

patch_mlnx_ofed2404plus() {
# providers/mlx4/CMakeLists.txt
enable_mlx4_modprobe_install '${CMAKE_INSTALL_MODPROBEDIR}/' || return 1
echo Patched: providers/mlx4/CMakeLists.txt
echo

# rdma-core.spec
cat > rdma-core.spec.patch << 'EOF'
--- rdma-core.spec		2024-04-22 17:41:21.000000000 -0300
+++ rdma-core.spec.patched	2026-04-11 12:00:00.000000000 -0300
@@ -467,10 +467,4 @@
 rm -rf %{buildroot}/%{_initrddir}/
 %endif
-
-rm -f %{buildroot}%{_sysconfdir}/libibverbs.d/efa.driver
-rm -f %{buildroot}%{_sysconfdir}/libibverbs.d/mlx4.driver
-rm -f %{buildroot}%{_libdir}/libibverbs/libefa-rdmav*.so
-rm -f %{buildroot}%{_libdir}/libibverbs/libmlx4-rdmav*.so
-
 %post -n rdma-core
 if [ -x /sbin/udevadm ]; then
@@ -515,9 +511,9 @@
 %doc installed_docs/70-persistent-ipoib.rules
 %config(noreplace) %{_sysconfdir}/rdma/mlx4.conf
 %config(noreplace) %{_sysconfdir}/rdma/modules/rdma.conf
-%if 0
 %dir %{_sysconfdir}/modprobe.d
 %config(noreplace) %{_sysconfdir}/modprobe.d/mlx4.conf
+%if 0
 %config(noreplace) %{_sysconfdir}/modprobe.d/truescale.conf
 %endif
 %dir %{dracutlibdir}
@@ -689,6 +685,8 @@
 %{_libdir}/libmlx4.so.*
 %{_libdir}/libmlx5.so.*
 %endif
+%config(noreplace) %{_sysconfdir}/libibverbs.d/efa.driver
+%config(noreplace) %{_sysconfdir}/libibverbs.d/mlx4.driver
 %config(noreplace) %{_sysconfdir}/libibverbs.d/mlx5.driver
 %doc installed_docs/libibverbs.md
EOF

patch_checked rdma-core.spec rdma-core.spec.patch || return 1
rm -f rdma-core.spec.patch
echo Patched: rdma-core.spec
echo
}

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

patch_checked CMakeLists.txt CMakeLists.txt.patch || return 1
rm -f CMakeLists.txt.patch
echo Patched: CMakeLists.txt
echo

# providers/mlx4/CMakeLists.txt
enable_mlx4_modprobe_install '${CMAKE_INSTALL_SYSCONFDIR}/modprobe.d/' || return 1
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

patch_checked pyverbs/CMakeLists.txt CMakeLists.txt.patch || return 1
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

patch_checked rdma-core.spec rdma-core.spec.patch || return 1
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

patch_checked CMakeLists.txt CMakeLists.txt.patch || return 1
rm -f CMakeLists.txt.patch
echo Patched: CMakeLists.txt
echo

# providers/mlx4/CMakeLists.txt
enable_mlx4_modprobe_install '${CMAKE_INSTALL_SYSCONFDIR}/modprobe.d/' || return 1
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

patch_checked pyverbs/CMakeLists.txt CMakeLists.txt.patch || return 1
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

patch_checked rdma-core.spec rdma-core.spec.patch || return 1
rm -f rdma-core.spec.patch
echo Patched: rdma-core.spec
echo
}

patch_mlnx_ofed49() {
# CMakeLists.txt
cat > CMakeLists.txt.patch << 'EOF'
--- CMakeLists.txt		2021-04-23 07:31:00.000000000 -0300
+++ CMakeLists.txt.patched	2022-03-19 00:11:01.247634859 -0300
@@ -624,8 +624,10 @@
 if (0)
 add_subdirectory(providers/bnxt_re)
 add_subdirectory(providers/cxgb4) # NO SPARSE
+endif()
 add_subdirectory(providers/efa)
 add_subdirectory(providers/efa/man)
+if (0)
 add_subdirectory(providers/hns)
 add_subdirectory(providers/i40iw) # NO SPARSE
 endif()
EOF

patch_checked CMakeLists.txt CMakeLists.txt.patch || return 1
rm -f CMakeLists.txt.patch
echo Patched: CMakeLists.txt
echo

# rdma-core.spec
cat > rdma-core.spec.patch << 'EOF'
--- rdma-core.spec	2021-04-23 07:31:00.000000000 -0300
+++ rdma-core.spec.patched	2022-03-19 00:27:13.436049287 -0300
@@ -263,6 +263,7 @@
 
 Device-specific plug-in ibverbs userspace drivers are included:
 
+- libefa: Amazon Elastic Fabric Adapter
 - libmlx4: Mellanox ConnectX-3 InfiniBand HCA
 - libmlx5: Mellanox Connect-IB/X-4+ InfiniBand HCA
 
@@ -540,10 +541,12 @@
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
@@ -638,6 +641,7 @@
 %files -n libibverbs
 %dir %{_sysconfdir}/libibverbs.d
 %dir %{_libdir}/libibverbs
+%{_libdir}/libefa.so.*
 %{_libdir}/libibverbs*.so.*
 %{_libdir}/libibverbs/*.so
 %ifnarch s390x s390
EOF

patch_checked rdma-core.spec rdma-core.spec.patch || return 1
rm -f rdma-core.spec.patch
echo Patched: rdma-core.spec
echo
}

detect_mlnx_ofed_version() {
	if [ -n "${MLNX_OFED_VERSION_OVERRIDE:-}" ]; then
		MLNX_OFED_VERSION=$MLNX_OFED_VERSION_OVERRIDE
	else
		MLNX_OFED_VERSION=`ofed_info -s | cut -f 2- -d- | cut -f 1 -d:`
	fi
}

set_release_metadata() {
	RDMA_CORE_VERSION=$1
	RDMA_CORE_MINOR_VERSION=$2
	RDMA_CORE_NEW_VERSION=$3
	PATCH_FAMILY=$4
}

load_release_metadata() {
	case $MLNX_OFED_VERSION in
		25.01-0.6.0.0)
			# MLNX OFED 25.01-0.6.0.0 version info
			# https://linux.mellanox.com/public/repo/mlnx_ofed/25.01-0.6.0.0/MLNX_OFED_SRC-25.01-0.6.0.0.tgz
			set_release_metadata "2501mlnx56" "1.2501060" "2501061.versatushpc" "2404plus"
			;;
		24.10-0.6.8.0|24.10-0.6.8.1|24.10-0.7.0.0|24.10-1.1.4.0|24.10-1.1.4.0.105|24.10-2.1.8.0|24.10-3.2.5.0|24.10-4.1.4.0)
			# MLNX OFED 24.10 version info
			# https://linux.mellanox.com/public/repo/mlnx_ofed/latest-24.10/
			set_release_metadata "2410mlnx54" "1.2410068" "2410069.versatushpc" "2404plus"
			;;
		24.07-0.6.1.0)
			# MLNX OFED 24.07-0.6.1.0 version info
			# https://linux.mellanox.com/public/repo/mlnx_ofed/24.07-0.6.1.0/
			set_release_metadata "2407mlnx52" "1.2407061" "2407062.versatushpc" "2404plus"
			;;
		24.07-0.6.0.0)
			# MLNX OFED 24.07-0.6.0.0 version info
			# https://linux.mellanox.com/public/repo/mlnx_ofed/24.07-0.6.0.0/MLNX_OFED_SRC-24.07-0.6.0.0.tgz
			set_release_metadata "2407mlnx52" "1.2407060" "2407061.versatushpc" "2404plus"
			;;
		24.04-0.6.6.0|24.04-0.7.0.0)
			# MLNX OFED 24.04 version info
			# https://linux.mellanox.com/public/repo/mlnx_ofed/latest-24.04/
			set_release_metadata "2404mlnx51" "1.2404066" "2404067.versatushpc" "2404plus"
			;;
		24.04-0.6.5.0)
			# MLNX OFED 24.04-0.6.5.0 version info
			# https://linux.mellanox.com/public/repo/mlnx_ofed/24.04-0.6.5.0/MLNX_OFED_SRC-24.04-0.6.5.0.tgz
			set_release_metadata "2404mlnx51" "1.2404065" "2404066.versatushpc" "2404plus"
			;;
		24.01-0.3.3.1)
			# MLNX OFED 24.01-0.3.3.1 version info
			# https://linux.mellanox.com/public/repo/mlnx_ofed/24.01-0.3.3.1/
			set_release_metadata "2307mlnx47" "1.2401033" "2401034.versatushpc" "59"
			;;
		23.10-4.0.9.1|23.10-6.1.6.1)
			# MLNX OFED 23.10 version info
			# https://linux.mellanox.com/public/repo/mlnx_ofed/latest-23.10/
			set_release_metadata "2307mlnx47" "1.2310409" "2310410.versatushpc" "59"
			;;
		23.10-3.2.2.0)
			# MLNX OFED 23.10-3.2.2.0 version info
			# https://linux.mellanox.com/public/repo/mlnx_ofed/23.10-3.2.2.0/
			set_release_metadata "2307mlnx47" "1.2310322" "2310323.versatushpc" "59"
			;;
		23.10-2.1.3.1|23.10-2.1.3.1.201)
			# MLNX OFED 23.10 version info
			# https://linux.mellanox.com/public/repo/mlnx_ofed/23.10-2.1.3.1/
			set_release_metadata "2307mlnx47" "1.2310213" "2310214.versatushpc" "59"
			;;
		23.10-1.1.9.0)
			# MLNX OFED 23.10-1.1.9.0 version info
			# https://linux.mellanox.com/public/repo/mlnx_ofed/23.10-1.1.9.0/
			set_release_metadata "2307mlnx47" "1.2310119" "2310120.versatushpc" "59"
			;;
		23.10-0.5.5.0)
			# MLNX OFED 23.10-0.5.5.0 version info
			# https://linux.mellanox.com/public/repo/mlnx_ofed/23.10-0.5.5.0/
			set_release_metadata "2307mlnx47" "1.2310055" "2310056.versatushpc" "59"
			;;
		23.07-0.5.0.0|23.07-0.5.1.2)
			# MLNX OFED 23.07 version info
			# https://linux.mellanox.com/public/repo/mlnx_ofed/latest-23.07/
			set_release_metadata "2307mlnx47" "1.2307050" "2307051.versatushpc" "59"
			;;
		23.04-1.1.3.0)
			# MLNX OFED 23.04-1.1.3.0 version info
			# https://linux.mellanox.com/public/repo/mlnx_ofed/23.04-1.1.3.0/
			set_release_metadata "2304mlnx44" "1.2304113" "2304114.versatushpc" "59"
			;;
		23.04-0.5.3.3)
			# MLNX OFED 23.04-0.5.3.3 version info
			# https://linux.mellanox.com/public/repo/mlnx_ofed/23.04-0.5.3.3/
			set_release_metadata "2304mlnx44" "1.2304053" "2304054.versatushpc" "59"
			;;
		5.9-0.5.6.0.127)
			# MLNX OFED 5.9-0.5.6.0.127 version info
			# https://content.mellanox.com/ofed/MLNX_OFED-5.9-0.5.6.0.127/MLNX_OFED_SRC-5.9-0.5.6.0.127.tgz
			RDMA_CORE_VERSION="59mlnx44"
			RDMA_CORE_MINOR_VERSION="1.59056.0127"
			RDMA_CORE_NEW_VERSION="59056.0128.versatushpc"
			PATCH_FAMILY="59"
			;;
		5.9-0.5.6.0.125)
			# MLNX OFED 5.9-0.5.6.0.125 version info
			# https://content.mellanox.com/ofed/MLNX_OFED-5.9-0.5.6.0.125/MLNX_OFED_SRC-5.9-0.5.6.0.125.tgz
			RDMA_CORE_VERSION="59mlnx44"
			RDMA_CORE_MINOR_VERSION="1.59056.0125"
			RDMA_CORE_NEW_VERSION="59056.0126.versatushpc"
			PATCH_FAMILY="59"
			;;
		5.9-0.5.6.0)
			# MLNX OFED 5.9-0.5.6.0 version info
			# https://content.mellanox.com/ofed/MLNX_OFED-5.9-0.5.6.0/MLNX_OFED_SRC-5.9-0.5.6.0.tgz
			RDMA_CORE_VERSION="59mlnx44"
			RDMA_CORE_MINOR_VERSION="1.59056"
			RDMA_CORE_NEW_VERSION="59057.versatushpc"
			PATCH_FAMILY="59"
			;;
		5.8-6.0.4.2)
			# MLNX OFED 5.8-6.0.4.2 version info
			# https://content.mellanox.com/ofed/MLNX_OFED-5.8-6.0.4.2/MLNX_OFED_SRC-5.8-6.0.4.2.tgz
			RDMA_CORE_VERSION="58mlnx43"
			RDMA_CORE_MINOR_VERSION="1.58604"
			RDMA_CORE_NEW_VERSION="58605.versatushpc"
			PATCH_FAMILY="56plus"
			;;
		5.8-7.0.6.1)
			# MLNX OFED 5.8-7.0.6.1 version info
			# https://content.mellanox.com/ofed/MLNX_OFED-5.8-7.0.6.1/MLNX_OFED_SRC-5.8-7.0.6.1.tgz
			RDMA_CORE_VERSION="58mlnx43"
			RDMA_CORE_MINOR_VERSION="1.58706"
			RDMA_CORE_NEW_VERSION="58707.versatushpc"
			PATCH_FAMILY="56plus"
			;;
		5.8-5.1.1.2)
			# MLNX OFED 5.8-5.1.1.2 version info
			# https://content.mellanox.com/ofed/MLNX_OFED-5.8-5.1.1.2/MLNX_OFED_SRC-5.8-5.1.1.2.tgz
			RDMA_CORE_VERSION="58mlnx43"
			RDMA_CORE_MINOR_VERSION="1.58511"
			RDMA_CORE_NEW_VERSION="58512.versatushpc"
			PATCH_FAMILY="56plus"
			;;
		5.8-4.1.5.0)
			# MLNX OFED 5.8-4.1.5.0 version info
			# https://content.mellanox.com/ofed/MLNX_OFED-5.8-4.1.5.0/MLNX_OFED_SRC-5.8-4.1.5.0.tgz
			RDMA_CORE_VERSION="58mlnx43"
			RDMA_CORE_MINOR_VERSION="1.58415"
			RDMA_CORE_NEW_VERSION="58416.versatushpc"
			PATCH_FAMILY="56plus"
			;;
		5.8-3.0.7.0.101)
			# MLNX OFED 5.8-3.0.7.0.101 version info
			# https://content.mellanox.com/ofed/MLNX_OFED-5.8-3.0.7.0.101/MLNX_OFED_SRC-5.8-3.0.7.0.101.tgz
			RDMA_CORE_VERSION="58mlnx43"
			RDMA_CORE_MINOR_VERSION="1.58307.0101"
			RDMA_CORE_NEW_VERSION="58307.0102.versatushpc"
			PATCH_FAMILY="56plus"
			;;
		5.8-3.0.7.0)
			# MLNX OFED 5.8-3.0.7.0 version info
			# https://content.mellanox.com/ofed/MLNX_OFED-5.8-3.0.7.0/MLNX_OFED_SRC-5.8-3.0.7.0.tgz
			RDMA_CORE_VERSION="58mlnx43"
			RDMA_CORE_MINOR_VERSION="1.58307"
			RDMA_CORE_NEW_VERSION="58308.versatushpc"
			PATCH_FAMILY="56plus"
			;;
		5.8-2.0.3.0)
			# MLNX OFED 5.8-2.0.3.0 version info
			# https://content.mellanox.com/ofed/MLNX_OFED-5.8-2.0.3.0/MLNX_OFED_SRC-5.8-2.0.3.0.tgz
			RDMA_CORE_VERSION="58mlnx43"
			RDMA_CORE_MINOR_VERSION="1.58203"
			RDMA_CORE_NEW_VERSION="58204.versatushpc"
			PATCH_FAMILY="56plus"
			;;
		5.8-1.1.2.1)
			# MLNX OFED 5.8-1.1.2.1 version info
			# https://content.mellanox.com/ofed/MLNX_OFED-5.8-1.1.2.1/MLNX_OFED_SRC-5.8-1.1.2.1.tgz
			RDMA_CORE_VERSION="58mlnx43"
			RDMA_CORE_MINOR_VERSION="1.58112"
			RDMA_CORE_NEW_VERSION="58113.versatushpc"
			PATCH_FAMILY="56plus"
			;;
		5.8-1.0.1.1)
			# MLNX OFED 5.8-1.0.1.1 version info
			# https://content.mellanox.com/ofed/MLNX_OFED-5.8-1.0.1.1/MLNX_OFED_SRC-5.8-1.0.1.1.tgz
			RDMA_CORE_VERSION="58mlnx43"
			RDMA_CORE_MINOR_VERSION="1.58101"
			RDMA_CORE_NEW_VERSION="58102.versatushpc"
			PATCH_FAMILY="56plus"
			;;
		5.7-1.0.2.0)
			# MLNX OFED 5.7-1.0.2.0 version info
			# https://content.mellanox.com/ofed/MLNX_OFED-5.7-1.0.2.0/MLNX_OFED_SRC-5.7-1.0.2.0.tgz
			RDMA_CORE_VERSION="56mlnx40"
			RDMA_CORE_MINOR_VERSION="1.57102"
			RDMA_CORE_NEW_VERSION="57103.versatushpc"
			PATCH_FAMILY="56plus"
			;;
		5.6-2.0.9.0)
			# MLNX OFED 5.6-2.0.9.0 version info
			# https://content.mellanox.com/ofed/MLNX_OFED-5.6-2.0.9.0/MLNX_OFED_SRC-5.6-2.0.9.0.tgz
			RDMA_CORE_VERSION="56mlnx40"
			RDMA_CORE_MINOR_VERSION="1.56209"
			RDMA_CORE_NEW_VERSION="56210.versatushpc"
			PATCH_FAMILY="56plus"
			;;
		5.6-1.0.3.3)
			# MLNX OFED 5.6-1.0.3.3 version info
			# https://content.mellanox.com/ofed/MLNX_OFED-5.6-1.0.3.3/MLNX_OFED_SRC-5.6-1.0.3.3.tgz
			RDMA_CORE_VERSION="56mlnx40"
			RDMA_CORE_MINOR_VERSION="1.56103"
			RDMA_CORE_NEW_VERSION="56104.versatushpc"
			PATCH_FAMILY="56plus"
			;;
		5.5-1.0.3.2)
			# MLNX OFED 5.5-1.0.3.2 version info
			# https://content.mellanox.com/ofed/MLNX_OFED-5.5-1.0.3.2/MLNX_OFED_SRC-5.5-1.0.3.2.tgz
			RDMA_CORE_VERSION="55mlnx37"
			RDMA_CORE_MINOR_VERSION="1.55103"
			RDMA_CORE_NEW_VERSION="55104.versatushpc"
			PATCH_FAMILY="55"
			;;
		5.4-3.7.5.0)
			# MLNX OFED 5.4-3.7.5.0 version info
			# https://content.mellanox.com/ofed/MLNX_OFED-5.4-3.7.5.0/MLNX_OFED_SRC-5.4-3.7.5.0.tgz
			RDMA_CORE_VERSION="54mlnx1"
			RDMA_CORE_MINOR_VERSION="1.54375"
			RDMA_CORE_NEW_VERSION="54376.versatushpc"
			PATCH_FAMILY="54"
			;;
		5.4-3.6.8.1)
			# MLNX OFED 5.4-3.6.8.1 version info
			# https://content.mellanox.com/ofed/MLNX_OFED-5.4-3.6.8.1/MLNX_OFED_SRC-5.4-3.6.8.1.tgz
			RDMA_CORE_VERSION="54mlnx1"
			RDMA_CORE_MINOR_VERSION="1.54368"
			RDMA_CORE_NEW_VERSION="54369.versatushpc"
			PATCH_FAMILY="54"
			;;
		5.4-3.5.8.0)
			# MLNX OFED 5.4-3.5.8.0 version info
			# https://content.mellanox.com/ofed/MLNX_OFED-5.4-3.5.8.0/MLNX_OFED_SRC-5.4-3.5.8.0.tgz
			RDMA_CORE_VERSION="54mlnx1"
			RDMA_CORE_MINOR_VERSION="1.54358"
			RDMA_CORE_NEW_VERSION="54359.versatushpc"
			PATCH_FAMILY="54"
			;;
		5.4-3.4.0.0)
			# MLNX OFED 5.4-3.4.0.0 version info
			# https://content.mellanox.com/ofed/MLNX_OFED-5.4-3.4.0.0/MLNX_OFED_SRC-5.4-3.4.0.0.tgz
			RDMA_CORE_VERSION="54mlnx1"
			RDMA_CORE_MINOR_VERSION="1.54340"
			RDMA_CORE_NEW_VERSION="54341.versatushpc"
			PATCH_FAMILY="54"
			;;
		5.4-3.2.7.2.3)
			# MLNX OFED 5.4-3.2.7.2.3 version info
			# https://content.mellanox.com/ofed/MLNX_OFED-5.4-3.2.7.2.3/MLNX_OFED_SRC-5.4-3.2.7.2.3.tgz
			RDMA_CORE_VERSION="54mlnx1"
			RDMA_CORE_MINOR_VERSION="1.54327.23"
			RDMA_CORE_NEW_VERSION="54327.24.versatushpc"
			PATCH_FAMILY="54"
			;;
		5.4-3.1.0.0)
			# MLNX OFED 5.4-3.1.0.0 version info
			# https://content.mellanox.com/ofed/MLNX_OFED-5.4-3.1.0.0/MLNX_OFED_SRC-5.4-3.1.0.0.tgz
			RDMA_CORE_VERSION="54mlnx1"
			RDMA_CORE_MINOR_VERSION="1.54310"
			RDMA_CORE_NEW_VERSION="54311.versatushpc"
			PATCH_FAMILY="54"
			;;
		5.4-3.0.3.0)
			# MLNX OFED 5.4-3.0.3.0 version info
			# https://content.mellanox.com/ofed/MLNX_OFED-5.4-3.0.3.0/MLNX_OFED_SRC-5.4-3.0.3.0.tgz
			RDMA_CORE_VERSION="54mlnx1"
			RDMA_CORE_MINOR_VERSION="1.54303"
			RDMA_CORE_NEW_VERSION="54304.versatushpc"
			PATCH_FAMILY="54"
			;;
		5.4-2.4.1.3)
			# MLNX OFED 5.4-2.4.1.3 version info
			# https://content.mellanox.com/ofed/MLNX_OFED-5.4-2.4.1.3/MLNX_OFED_SRC-5.4-2.4.1.3.tgz
			RDMA_CORE_VERSION="54mlnx1"
			RDMA_CORE_MINOR_VERSION="1.54241"
			RDMA_CORE_NEW_VERSION="54242.versatushpc"
			PATCH_FAMILY="54"
			;;
		5.4-1.0.3.0)
			# MLNX OFED 5.4-1.0.3.0 version info
			# https://content.mellanox.com/ofed/MLNX_OFED-5.4-1.0.3.0/MLNX_OFED_SRC-5.4-1.0.3.0.tgz
			RDMA_CORE_VERSION="54mlnx1"
			RDMA_CORE_MINOR_VERSION="1.54103"
			RDMA_CORE_NEW_VERSION="54104.versatushpc"
			PATCH_FAMILY="54"
			;;
		4.9-7.1.0.0)
			# MLNX OFED 4.9-7.1.0.0 version info
			# https://content.mellanox.com/ofed/MLNX_OFED-4.9-7.1.0.0/MLNX_OFED_SRC-4.9-7.1.0.0.tgz
			RDMA_CORE_VERSION="50mlnx1"
			RDMA_CORE_MINOR_VERSION="1.49710"
			RDMA_CORE_NEW_VERSION="49711.versatushpc"
			PATCH_FAMILY="49"
			;;
		4.9-6.0.6.0)
			# MLNX OFED 4.9-6.0.6.0 version info
			# https://content.mellanox.com/ofed/MLNX_OFED-4.9-6.0.6.0/MLNX_OFED_SRC-4.9-6.0.6.0.tgz
			RDMA_CORE_VERSION="50mlnx1"
			RDMA_CORE_MINOR_VERSION="1.49606"
			RDMA_CORE_NEW_VERSION="49607.versatushpc"
			PATCH_FAMILY="49"
			;;
		4.9-5.1.0.0)
			# MLNX OFED 4.9-5.1.0.0 version info
			# https://content.mellanox.com/ofed/MLNX_OFED-4.9-5.1.0.0/MLNX_OFED_SRC-4.9-5.1.0.0.tgz
			RDMA_CORE_VERSION="50mlnx1"
			RDMA_CORE_MINOR_VERSION="1.49510"
			RDMA_CORE_NEW_VERSION="49510.versatushpc"
			PATCH_FAMILY="49"
			;;
		4.9-4.1.7.0)
			# MLNX OFED 4.9-4.1.7.0 version info
			# https://content.mellanox.com/ofed/MLNX_OFED-4.9-4.1.7.0/MLNX_OFED_SRC-4.9-4.1.7.0.tgz
			RDMA_CORE_VERSION="50mlnx1"
			RDMA_CORE_MINOR_VERSION="1.49417"
			RDMA_CORE_NEW_VERSION="49418.versatushpc"
			PATCH_FAMILY="49"
			;;
		4.9-4.0.8.0)
			# MLNX OFED 4.9-4.0.8.0 version info
			# https://content.mellanox.com/ofed/MLNX_OFED-4.9-4.0.8.0/MLNX_OFED_SRC-4.9-4.0.8.0.tgz
			RDMA_CORE_VERSION="50mlnx1"
			RDMA_CORE_MINOR_VERSION="1.49408"
			RDMA_CORE_NEW_VERSION="49409.versatushpc"
			PATCH_FAMILY="49"
			;;
		4.9-3.1.5.0)
			# MLNX OFED 4.9-3.1.5.0 version info
			# https://content.mellanox.com/ofed/MLNX_OFED-4.9-3.1.5.0/MLNX_OFED_SRC-4.9-3.1.5.0.tgz
			RDMA_CORE_VERSION="50mlnx1"
			RDMA_CORE_MINOR_VERSION="1.49315"
			RDMA_CORE_NEW_VERSION="49316.versatushpc"
			PATCH_FAMILY="49"
			;;
		4.9-2.2.6.0)
			# MLNX OFED 4.9-2.2.6.0 version info
			# https://content.mellanox.com/ofed/MLNX_OFED-4.9-2.2.6.0/MLNX_OFED_SRC-4.9-2.2.6.0.tgz
			RDMA_CORE_VERSION="50mlnx1"
			RDMA_CORE_MINOR_VERSION="1.49226"
			RDMA_CORE_NEW_VERSION="49227.versatushpc"
			PATCH_FAMILY="49"
			;;
		4.9-2.2.4.0)
			# MLNX OFED 4.9-2.2.4.0 version info
			# https://content.mellanox.com/ofed/MLNX_OFED-4.9-2.2.4.0/MLNX_OFED_SRC-4.9-2.2.4.0.tgz
			RDMA_CORE_VERSION="50mlnx1"
			RDMA_CORE_MINOR_VERSION="1.49224"
			RDMA_CORE_NEW_VERSION="49225.versatushpc"
			PATCH_FAMILY="49"
			;;
		4.9-0.1.7.0)
			# MLNX OFED 4.9-0.1.7.0 version info
			# https://content.mellanox.com/ofed/MLNX_OFED-4.9-0.1.7.0/MLNX_OFED_SRC-4.9-0.1.7.0.tgz
			RDMA_CORE_VERSION="50mlnx1"
			RDMA_CORE_MINOR_VERSION="1.49017"
			RDMA_CORE_NEW_VERSION="49018.versatushpc"
			PATCH_FAMILY="49"
			;;
		*)
			return 1
			;;
	esac
	return 0
}

apply_release_patch() {
	case $PATCH_FAMILY in
		59)
			patch_mlnx_ofed59
			;;
		2404plus)
			patch_mlnx_ofed2404plus
			;;
		56plus)
			patch_mlnx_ofed56plus
			;;
		55)
			patch_mlnx_ofed55
			;;
		54)
			patch_mlnx_ofed54
			;;
		49)
			patch_mlnx_ofed49
			;;
		*)
			echo "Unsupported MLNX OFED release: $MLNX_OFED_VERSION"
			return 1
			;;
	esac
}

main() {
	detect_mlnx_ofed_version

	if [ -z "$MLNX_OFED_VERSION" ]; then
		echo Cannot detect MLNX OFED, is it installed?
		exit 1
	else
		echo Detected MLNX OFED release: $MLNX_OFED_VERSION
	fi

	if ! load_release_metadata; then
		echo "Unsupported MLNX OFED release: $MLNX_OFED_VERSION"
		exit 1
	fi

	mkdir -p $RPM_BUILD_ROOT/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
	mkdir -p $WORK_DIR
	cd $WORK_DIR

	echo Installing required dependencies...
	if rpm -q --quiet python3-Cython-ohpc ; then
		dnf remove -y python3-Cython-ohpc
	fi
	install_required_dependencies
	echo

	if [ ! -f MLNX_OFED_SRC-$MLNX_OFED_VERSION.tgz ] ; then
		echo Downloading MLNX OFED $MLNX_OFED_VERSION sources...
		download_source_bundle "$MLNX_OFED_VERSION"
	fi
	echo

	tar zxf MLNX_OFED_SRC-$MLNX_OFED_VERSION.tgz
	echo Extracting files from SRPMS...
	rpm2cpio MLNX_OFED_SRC-$MLNX_OFED_VERSION/SRPMS/rdma-core-$RDMA_CORE_VERSION-$RDMA_CORE_MINOR_VERSION.src.rpm | cpio -i
	echo

	rdma_core_archive=$(find_rdma_core_archive)
	if [ -z "$rdma_core_archive" ]; then
		echo "Cannot find rdma-core-$RDMA_CORE_VERSION source archive" >&2
		exit 1
	fi
	tar zxf "$rdma_core_archive"
	cd rdma-core-$RDMA_CORE_VERSION

	echo Patching MLNX OFED to add back support for MLX4 and EFA...
	echo
	sleep 1

	apply_release_patch

	cp -f rdma-core.spec ..
	cd ..

	sed -i s/Release:.*/Release:\ $RDMA_CORE_NEW_VERSION/g rdma-core.spec
	sed -i s/Source:.*/Source:\ rdma-core-%{version}-%{release}.tgz/g rdma-core.spec

	dnf_args=$(dnf_install_args)
	if ! rpm -q --quiet 'dnf-command(builddep)' && ! rpm -q --quiet dnf-plugins-core; then
		dnf install $dnf_args dnf-plugins-core
	fi
	dnf builddep $dnf_args rdma-core.spec

	tar czf rdma-core-$RDMA_CORE_VERSION-$RDMA_CORE_NEW_VERSION.tgz rdma-core-$RDMA_CORE_VERSION
	cp rdma-core-$RDMA_CORE_VERSION-$RDMA_CORE_NEW_VERSION.tgz $RPM_BUILD_ROOT/SOURCES

	echo Building RPMS... it may take a while
	rpmbuild --nodebuginfo --define "_topdir $RPM_BUILD_ROOT" -ba rdma-core.spec 2>/dev/null >/dev/null

	mkdir -p $RPMS_OUTPUT_DIR
	mv $RPM_BUILD_ROOT/RPMS/x86_64/* $RPMS_OUTPUT_DIR

	cd $RPMS_OUTPUT_DIR
	dnf install -y *

	rm -rf $WORK_DIR
	rm -rf $RPM_BUILD_ROOT

	echo
	echo Mellanox OFED installation has been patched for EFA \(libefa.so\) and MLX4 \(libmlx4.so\) support
	echo RPM packages are available at $RPMS_OUTPUT_DIR
	echo
	echo Done
}

if [ "${PATCH_MLNXOFED_LIBRARY_MODE:-0}" != "1" ]; then
	main "$@"
fi
