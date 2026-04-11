#!/bin/sh

set -eu

case $0 in
	*/*)
		self_path=$0
		;;
	*)
		self_path=$(command -v "$0" 2>/dev/null || printf '%s\n' "$0")
		;;
esac

script_dir=$(CDPATH= cd "$(dirname "$self_path")" && pwd)
repo_root=$(CDPATH= cd "$script_dir/.." && pwd)
cache_dir=${VERIFY_RELEASES_CACHE_DIR:-"${XDG_CACHE_HOME:-$HOME/.cache}/mlnxofed-patch/verify-releases"}

if [ "$#" -eq 0 ]; then
	echo "Usage: $0 <mlnx-ofed-version> [<mlnx-ofed-version> ...]" >&2
	exit 1
fi

for tool in curl rpm2cpio cpio tar patch rg; do
	if ! command -v "$tool" >/dev/null 2>&1; then
		echo "Missing required tool: $tool" >&2
		exit 1
	fi
done

mkdir -p "$cache_dir"
work_root=$(mktemp -d)
trap 'rm -rf "$work_root"' 0

PATCH_MLNXOFED_LIBRARY_MODE=1 . "$repo_root/patch-mlnxofed.sh"

download_source_rpm() {
	version=$1
	rpm_name=$2
	release_root=$3
	rpm_path=$4
	source_bundle_name="MLNX_OFED_SRC-$version.tgz"
	source_bundle_cache_path="$cache_dir/$source_bundle_name"

	if curl -fsSL "https://linux.mellanox.com/public/repo/mlnx_ofed/$version/SRPMS/$rpm_name" -o "$rpm_path" 2>/dev/null; then
		return 0
	fi

	if [ ! -f "$source_bundle_cache_path" ]; then
		if ! curl -fsSL "https://linux.mellanox.com/public/repo/mlnx_ofed/$version/$source_bundle_name" -o "$source_bundle_cache_path" 2>/dev/null; then
			curl -fsSL "https://content.mellanox.com/ofed/MLNX_OFED-$version/$source_bundle_name" -o "$source_bundle_cache_path"
		fi
	fi

	tar zxf "$source_bundle_cache_path" -C "$release_root"
	cp "$release_root/MLNX_OFED_SRC-$version/SRPMS/$rpm_name" "$rpm_path"
}

assert_contains() {
	file=$1
	text=$2

	if ! rg -F -- "$text" "$file" >/dev/null; then
		echo "Missing expected line in $file: $text" >&2
		return 1
	fi
}

assert_not_contains() {
	file=$1
	text=$2

	if rg -F -- "$text" "$file" >/dev/null; then
		echo "Unexpected line in $file: $text" >&2
		return 1
	fi
}

assert_multiline_contains() {
	file=$1
	text=$2

	if ! perl -e 'my ($pattern, $file) = @ARGV; local $/; open my $fh, "<", $file or die $!; my $content = <$fh>; exit(index($content, $pattern) >= 0 ? 0 : 1);' -- "$text" "$file"; then
		echo "Missing expected block in $file" >&2
		return 1
	fi
}

find_rdma_core_archive() {
	find . -maxdepth 1 \( -name "rdma-core-$RDMA_CORE_VERSION.tgz" -o -name "rdma-core-$RDMA_CORE_VERSION.tar.gz" \) | sed -n '1p'
}

verify_modern_source_markers() {
	install_dest=$1

	assert_contains CMakeLists.txt 'add_subdirectory(providers/efa)'
	assert_contains CMakeLists.txt 'add_subdirectory(providers/efa/man)'
	assert_contains CMakeLists.txt 'add_subdirectory(providers/mlx4)'
	assert_contains CMakeLists.txt 'add_subdirectory(providers/mlx4/man)'
	assert_contains providers/mlx4/CMakeLists.txt 'if (0)'
	assert_contains providers/mlx4/CMakeLists.txt "install(FILES \"mlx4.conf\" DESTINATION \"$install_dest\")"
	assert_contains pyverbs/CMakeLists.txt 'if (0)'
	assert_contains pyverbs/CMakeLists.txt 'add_subdirectory(providers/efa)'
	assert_multiline_contains rdma-core.spec '%config(noreplace) %{_sysconfdir}/rdma/mlx4.conf
%config(noreplace) %{_sysconfdir}/rdma/modules/rdma.conf
%if 0
%dir %{_sysconfdir}/modprobe.d
%config(noreplace) %{_sysconfdir}/modprobe.d/mlx4.conf
%config(noreplace) %{_sysconfdir}/modprobe.d/truescale.conf
%endif'
	assert_not_contains rdma-core.spec '%{_libdir}/libefa.so.*'
}

verify_modern_patched_tree() {
	install_dest=$1

	assert_contains CMakeLists.txt 'add_subdirectory(providers/efa)'
	assert_contains CMakeLists.txt 'add_subdirectory(providers/efa/man)'
	assert_contains CMakeLists.txt 'add_subdirectory(providers/mlx4)'
	assert_contains CMakeLists.txt 'add_subdirectory(providers/mlx4/man)'
	assert_contains providers/mlx4/CMakeLists.txt "install(FILES \"mlx4.conf\" DESTINATION \"$install_dest\")"
	assert_not_contains providers/mlx4/CMakeLists.txt 'if (0)'
	assert_contains pyverbs/CMakeLists.txt 'add_subdirectory(providers/efa)'
	assert_not_contains pyverbs/CMakeLists.txt 'if (0)'
	assert_contains rdma-core.spec '- libefa: Amazon Elastic Fabric Adapter'
	assert_contains rdma-core.spec '- libmlx4: Mellanox ConnectX-3 InfiniBand HCA'
	assert_multiline_contains rdma-core.spec '%config(noreplace) %{_sysconfdir}/rdma/mlx4.conf
%config(noreplace) %{_sysconfdir}/rdma/modules/rdma.conf
%dir %{_sysconfdir}/modprobe.d
%config(noreplace) %{_sysconfdir}/modprobe.d/mlx4.conf
%if 0
%config(noreplace) %{_sysconfdir}/modprobe.d/truescale.conf
%endif'
	assert_contains rdma-core.spec '%config(noreplace) %{_sysconfdir}/modprobe.d/mlx4.conf'
	assert_contains rdma-core.spec '%{_mandir}/man3/efadv*'
	assert_contains rdma-core.spec '%{_mandir}/man7/efadv*'
	assert_contains rdma-core.spec '%{_mandir}/man3/mlx4dv*'
	assert_contains rdma-core.spec '%{_mandir}/man7/mlx4dv*'
	assert_contains rdma-core.spec '%{_libdir}/libefa.so.*'
	assert_contains rdma-core.spec '%{_libdir}/libmlx4.so.*'
}

verify_2404plus_source_markers() {
	assert_contains CMakeLists.txt 'add_subdirectory(providers/efa)'
	assert_contains CMakeLists.txt 'add_subdirectory(providers/mlx4)'
	assert_contains providers/mlx4/CMakeLists.txt 'if (0)'
	assert_contains providers/mlx4/CMakeLists.txt 'install(FILES "mlx4.conf" DESTINATION "${CMAKE_INSTALL_MODPROBEDIR}/")'
	assert_contains rdma-core.spec 'rm -f %{buildroot}%{_sysconfdir}/libibverbs.d/efa.driver'
	assert_contains rdma-core.spec 'rm -f %{buildroot}%{_sysconfdir}/libibverbs.d/mlx4.driver'
	assert_contains rdma-core.spec 'rm -f %{buildroot}%{_libdir}/libibverbs/libefa-rdmav*.so'
	assert_contains rdma-core.spec 'rm -f %{buildroot}%{_libdir}/libibverbs/libmlx4-rdmav*.so'
	assert_multiline_contains rdma-core.spec '%config(noreplace) %{_sysconfdir}/rdma/mlx4.conf
%config(noreplace) %{_sysconfdir}/rdma/modules/rdma.conf
%if 0
%dir %{_sysconfdir}/modprobe.d
%config(noreplace) %{_sysconfdir}/modprobe.d/mlx4.conf
%config(noreplace) %{_sysconfdir}/modprobe.d/truescale.conf
%endif'
	assert_contains rdma-core.spec '%{_libdir}/libefa.so.*'
	assert_contains rdma-core.spec '%{_libdir}/libmlx4.so.*'
	assert_not_contains rdma-core.spec '%config(noreplace) %{_sysconfdir}/libibverbs.d/efa.driver'
	assert_not_contains rdma-core.spec '%config(noreplace) %{_sysconfdir}/libibverbs.d/mlx4.driver'
}

verify_2404plus_patched_tree() {
	assert_contains CMakeLists.txt 'add_subdirectory(providers/efa)'
	assert_contains CMakeLists.txt 'add_subdirectory(providers/mlx4)'
	assert_contains providers/mlx4/CMakeLists.txt 'install(FILES "mlx4.conf" DESTINATION "${CMAKE_INSTALL_MODPROBEDIR}/")'
	assert_not_contains providers/mlx4/CMakeLists.txt 'if (0)'
	assert_not_contains rdma-core.spec 'rm -f %{buildroot}%{_sysconfdir}/libibverbs.d/efa.driver'
	assert_not_contains rdma-core.spec 'rm -f %{buildroot}%{_sysconfdir}/libibverbs.d/mlx4.driver'
	assert_not_contains rdma-core.spec 'rm -f %{buildroot}%{_libdir}/libibverbs/libefa-rdmav*.so'
	assert_not_contains rdma-core.spec 'rm -f %{buildroot}%{_libdir}/libibverbs/libmlx4-rdmav*.so'
	assert_multiline_contains rdma-core.spec '%config(noreplace) %{_sysconfdir}/rdma/mlx4.conf
%config(noreplace) %{_sysconfdir}/rdma/modules/rdma.conf
%dir %{_sysconfdir}/modprobe.d
%config(noreplace) %{_sysconfdir}/modprobe.d/mlx4.conf
%if 0
%config(noreplace) %{_sysconfdir}/modprobe.d/truescale.conf
%endif'
	assert_contains rdma-core.spec '%{_libdir}/libefa.so.*'
	assert_contains rdma-core.spec '%{_libdir}/libmlx4.so.*'
	assert_contains rdma-core.spec '%config(noreplace) %{_sysconfdir}/libibverbs.d/efa.driver'
	assert_contains rdma-core.spec '%config(noreplace) %{_sysconfdir}/libibverbs.d/mlx4.driver'
	assert_contains rdma-core.spec '%config(noreplace) %{_sysconfdir}/libibverbs.d/mlx5.driver'
}

verify_56plus_source_markers() {
	install_dest=$1

	assert_multiline_contains CMakeLists.txt 'if (HAVE_COHERENT_DMA)
if (0)
add_subdirectory(providers/bnxt_re)
add_subdirectory(providers/cxgb4) # NO SPARSE
add_subdirectory(providers/efa)
add_subdirectory(providers/efa/man)
add_subdirectory(providers/hns)
add_subdirectory(providers/irdma)
add_subdirectory(providers/mlx4)
add_subdirectory(providers/mlx4/man)
endif()
add_subdirectory(providers/mlx5)
add_subdirectory(providers/mlx5/man)'
	assert_contains providers/mlx4/CMakeLists.txt 'if (0)'
	assert_contains providers/mlx4/CMakeLists.txt "install(FILES \"mlx4.conf\" DESTINATION \"$install_dest\")"
	assert_contains pyverbs/CMakeLists.txt 'if (0)'
	assert_contains pyverbs/CMakeLists.txt 'add_subdirectory(providers/efa)'
	assert_multiline_contains rdma-core.spec '%config(noreplace) %{_sysconfdir}/rdma/mlx4.conf
%config(noreplace) %{_sysconfdir}/rdma/modules/rdma.conf
%if 0
%dir %{_sysconfdir}/modprobe.d
%config(noreplace) %{_sysconfdir}/modprobe.d/mlx4.conf
%config(noreplace) %{_sysconfdir}/modprobe.d/truescale.conf
%endif'
	assert_contains rdma-core.spec '%{sysmodprobedir}/libmlx4.conf'
	assert_not_contains rdma-core.spec '%{_libdir}/libefa.so.*'
}

verify_56plus_patched_tree() {
	install_dest=$1

assert_multiline_contains CMakeLists.txt 'if (HAVE_COHERENT_DMA)
if (0)
add_subdirectory(providers/bnxt_re)
add_subdirectory(providers/cxgb4) # NO SPARSE
endif()
add_subdirectory(providers/efa)
add_subdirectory(providers/efa/man)
if (0)
add_subdirectory(providers/hns)
add_subdirectory(providers/irdma)
endif()
add_subdirectory(providers/mlx4)
add_subdirectory(providers/mlx4/man)
add_subdirectory(providers/mlx5)
add_subdirectory(providers/mlx5/man)'
	assert_contains providers/mlx4/CMakeLists.txt "install(FILES \"mlx4.conf\" DESTINATION \"$install_dest\")"
	assert_not_contains providers/mlx4/CMakeLists.txt 'if (0)'
	assert_contains pyverbs/CMakeLists.txt 'add_subdirectory(providers/efa)'
	assert_not_contains pyverbs/CMakeLists.txt 'if (0)'
	assert_contains rdma-core.spec '- libefa: Amazon Elastic Fabric Adapter'
	assert_contains rdma-core.spec '- libmlx4: Mellanox ConnectX-3 InfiniBand HCA'
	assert_multiline_contains rdma-core.spec '%config(noreplace) %{_sysconfdir}/rdma/mlx4.conf
%config(noreplace) %{_sysconfdir}/rdma/modules/rdma.conf
%dir %{_sysconfdir}/modprobe.d
%config(noreplace) %{_sysconfdir}/modprobe.d/mlx4.conf
%if 0
%config(noreplace) %{_sysconfdir}/modprobe.d/truescale.conf
%endif'
	assert_contains rdma-core.spec '%{sysmodprobedir}/libmlx4.conf'
	assert_contains rdma-core.spec '%{_mandir}/man3/efadv*'
	assert_contains rdma-core.spec '%{_mandir}/man7/efadv*'
	assert_contains rdma-core.spec '%{_mandir}/man3/mlx4dv*'
	assert_contains rdma-core.spec '%{_mandir}/man7/mlx4dv*'
	assert_contains rdma-core.spec '%{_libdir}/libefa.so.*'
	assert_contains rdma-core.spec '%{_libdir}/libmlx4.so.*'
}

verify_49_source_markers() {
	assert_contains CMakeLists.txt 'add_subdirectory(providers/efa)'
	assert_contains CMakeLists.txt 'add_subdirectory(providers/efa/man)'
	assert_not_contains rdma-core.spec '%{_libdir}/libefa.so.*'
}

verify_49_patched_tree() {
	assert_contains CMakeLists.txt 'add_subdirectory(providers/efa)'
	assert_contains CMakeLists.txt 'add_subdirectory(providers/efa/man)'
	assert_contains rdma-core.spec '- libefa: Amazon Elastic Fabric Adapter'
	assert_contains rdma-core.spec '%{_mandir}/man3/efadv*'
	assert_contains rdma-core.spec '%{_mandir}/man7/efadv*'
	assert_contains rdma-core.spec '%{_libdir}/libefa.so.*'
}

verify_51to53_source_markers() {
	assert_multiline_contains CMakeLists.txt 'if (0)
add_subdirectory(providers/bnxt_re)
add_subdirectory(providers/cxgb4) # NO SPARSE
add_subdirectory(providers/efa)
add_subdirectory(providers/efa/man)
add_subdirectory(providers/hns)
add_subdirectory(providers/i40iw) # NO SPARSE
add_subdirectory(providers/mlx4)
add_subdirectory(providers/mlx4/man)
endif()
add_subdirectory(providers/mlx5)
add_subdirectory(providers/mlx5/man)'
	assert_contains providers/mlx4/CMakeLists.txt 'if (0)'
	assert_contains providers/mlx4/CMakeLists.txt 'install(FILES "mlx4.conf" DESTINATION "${CMAKE_INSTALL_SYSCONFDIR}/modprobe.d/")'
	assert_contains pyverbs/CMakeLists.txt 'if (0)'
	assert_contains pyverbs/CMakeLists.txt 'add_subdirectory(providers/efa)'
	assert_multiline_contains rdma-core.spec '%config(noreplace) %{_sysconfdir}/rdma/mlx4.conf
%config(noreplace) %{_sysconfdir}/rdma/rdma.conf
%config(noreplace) %{_sysconfdir}/rdma/sriov-vfs
%if 0
%config(noreplace) %{_sysconfdir}/modprobe.d/mlx4.conf
%config(noreplace) %{_sysconfdir}/modprobe.d/truescale.conf
%endif'
	assert_not_contains rdma-core.spec '- libefa: Amazon Elastic Fabric Adapter'
	assert_not_contains rdma-core.spec '%{_libdir}/libefa.so.*'
}

verify_51to53_patched_tree() {
	assert_multiline_contains CMakeLists.txt 'if (0)
add_subdirectory(providers/bnxt_re)
add_subdirectory(providers/cxgb4) # NO SPARSE
endif()
add_subdirectory(providers/efa)
add_subdirectory(providers/efa/man)
if (0)
add_subdirectory(providers/hns)
add_subdirectory(providers/i40iw) # NO SPARSE
endif()
add_subdirectory(providers/mlx4)
add_subdirectory(providers/mlx4/man)
add_subdirectory(providers/mlx5)
add_subdirectory(providers/mlx5/man)'
	assert_contains providers/mlx4/CMakeLists.txt 'install(FILES "mlx4.conf" DESTINATION "${CMAKE_INSTALL_SYSCONFDIR}/modprobe.d/")'
	assert_not_contains providers/mlx4/CMakeLists.txt 'if (0)'
	assert_contains pyverbs/CMakeLists.txt 'add_subdirectory(providers/efa)'
	assert_not_contains pyverbs/CMakeLists.txt 'if (0)'
	assert_contains rdma-core.spec '- libefa: Amazon Elastic Fabric Adapter'
	assert_contains rdma-core.spec '- libmlx4: Mellanox ConnectX-3 InfiniBand HCA'
	assert_multiline_contains rdma-core.spec '%config(noreplace) %{_sysconfdir}/rdma/mlx4.conf
%config(noreplace) %{_sysconfdir}/rdma/rdma.conf
%config(noreplace) %{_sysconfdir}/rdma/sriov-vfs
%dir %{_sysconfdir}/modprobe.d
%config(noreplace) %{_sysconfdir}/modprobe.d/mlx4.conf
%if 0
%config(noreplace) %{_sysconfdir}/modprobe.d/truescale.conf
%endif'
	assert_contains rdma-core.spec '%{_mandir}/man3/efadv*'
	assert_contains rdma-core.spec '%{_mandir}/man7/efadv*'
	assert_contains rdma-core.spec '%{_mandir}/man3/mlx4dv*'
	assert_contains rdma-core.spec '%{_mandir}/man7/mlx4dv*'
	assert_contains rdma-core.spec '%{_libdir}/libefa.so.*'
	assert_contains rdma-core.spec '%{_libdir}/libmlx4.so.*'
}

verify_source_markers() {
	case $PATCH_FAMILY in
		56plus)
			verify_56plus_source_markers '${CMAKE_INSTALL_MODPROBEDIR}/'
			;;
		59)
			verify_modern_source_markers '${CMAKE_INSTALL_MODPROBEDIR}/'
			;;
		2404plus)
			verify_2404plus_source_markers
			;;
		55|54)
			verify_modern_source_markers '${CMAKE_INSTALL_SYSCONFDIR}/modprobe.d/'
			;;
		49)
			verify_49_source_markers
			;;
		51to53)
			verify_51to53_source_markers
			;;
		*)
			echo "FAIL $version unsupported patch family $PATCH_FAMILY" >&2
			return 1
			;;
	esac
}

verify_patched_tree() {
	case $PATCH_FAMILY in
		56plus)
			verify_56plus_patched_tree '${CMAKE_INSTALL_MODPROBEDIR}/'
			;;
		59)
			verify_modern_patched_tree '${CMAKE_INSTALL_MODPROBEDIR}/'
			;;
		2404plus)
			verify_2404plus_patched_tree
			;;
		55|54)
			verify_modern_patched_tree '${CMAKE_INSTALL_SYSCONFDIR}/modprobe.d/'
			;;
		49)
			verify_49_patched_tree
			;;
		51to53)
			verify_51to53_patched_tree
			;;
		*)
			echo "FAIL $version unsupported patch family $PATCH_FAMILY" >&2
			return 1
			;;
	esac
}

verify_release() {
	version=$1

	MLNX_OFED_VERSION="$version"
	if ! load_release_metadata; then
		echo "FAIL $version unsupported release metadata"
		return 1
	fi

	rpm_name="rdma-core-$RDMA_CORE_VERSION-$RDMA_CORE_MINOR_VERSION.src.rpm"
	rpm_cache_path="$cache_dir/$rpm_name"
	release_root="$work_root/$version"

	if [ ! -f "$rpm_cache_path" ]; then
		download_source_rpm "$version" "$rpm_name" "$work_root" "$rpm_cache_path"
	fi

	mkdir -p "$release_root"
	cp "$rpm_cache_path" "$release_root/"

	cd "$release_root"
	rpm2cpio "$rpm_name" | cpio -idm >/dev/null 2>&1
	rdma_core_archive=$(find_rdma_core_archive)
	if [ -z "$rdma_core_archive" ]; then
		echo "FAIL $version missing rdma-core-$RDMA_CORE_VERSION source archive" >&2
		return 1
	fi
	tar zxf "$rdma_core_archive"
	cd "rdma-core-$RDMA_CORE_VERSION"

	verify_source_markers
	if ! apply_release_patch >"$release_root/patch.log" 2>&1; then
		cat "$release_root/patch.log" >&2
		return 1
	fi
	verify_patched_tree

	echo "PASS $version"
}

for version in "$@"; do
	verify_release "$version"
done
