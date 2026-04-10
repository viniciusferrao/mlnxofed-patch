#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)
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
trap 'rm -rf "$work_root"' EXIT

PATCH_MLNXOFED_LIBRARY_MODE=1 . "$repo_root/patch-mlnxofed.sh"

download_source_rpm() {
	local version="$1"
	local rpm_name="$2"
	local release_root="$3"
	local rpm_path="$4"
	local source_bundle_name="MLNX_OFED_SRC-$version.tgz"
	local source_bundle_cache_path="$cache_dir/$source_bundle_name"

	if curl -fsSL "https://linux.mellanox.com/public/repo/mlnx_ofed/$version/SRPMS/$rpm_name" -o "$rpm_path"; then
		return 0
	fi

	if [ ! -f "$source_bundle_cache_path" ]; then
		if ! curl -fsSL "https://linux.mellanox.com/public/repo/mlnx_ofed/$version/$source_bundle_name" -o "$source_bundle_cache_path"; then
			curl -fsSL "https://content.mellanox.com/ofed/MLNX_OFED-$version/$source_bundle_name" -o "$source_bundle_cache_path"
		fi
	fi

	tar zxf "$source_bundle_cache_path" -C "$release_root"
	cp "$release_root/MLNX_OFED_SRC-$version/SRPMS/$rpm_name" "$rpm_path"
}

verify_release() {
	local version="$1"
	local rpm_name
	local rpm_cache_path
	local release_root

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
	tar zxf "rdma-core-$RDMA_CORE_VERSION.tgz"
	cd "rdma-core-$RDMA_CORE_VERSION"

	apply_release_patch >/dev/null

	rg -F 'add_subdirectory(providers/efa)' CMakeLists.txt >/dev/null
	rg -F '%{_libdir}/libefa.so.*' rdma-core.spec >/dev/null

	echo "PASS $version"
}

for version in "$@"; do
	verify_release "$version"
done
