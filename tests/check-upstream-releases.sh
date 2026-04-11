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
upstream_url=${MLNX_OFED_UPSTREAM_URL:-https://linux.mellanox.com/public/repo/mlnx_ofed}
upstream_url=${upstream_url%/}

for tool in curl comm grep sed sort tr; do
	if ! command -v "$tool" >/dev/null 2>&1; then
		echo "Missing required tool: $tool" >&2
		exit 2
	fi
done

work_root=$(mktemp -d)
trap 'rm -rf "$work_root"' 0

upstream_versions=$work_root/upstream
known_versions=$work_root/known
ignored_versions=$work_root/ignored
candidate_versions=$work_root/candidates
missing_versions=$work_root/missing
skipped_versions=$work_root/skipped

curl -fsSL "$upstream_url/" |
	sed -n 's/.*href="\([0-9][^"/]*\)\/".*/\1/p' |
	LC_ALL=C sort -u > "$upstream_versions"

tr '`' '\n' < "$repo_root/README.md" |
	sed -n '/^[0-9][0-9.]*-[0-9A-Za-z.-][0-9A-Za-z.-]*$/p' |
	LC_ALL=C sort -u > "$known_versions"

if [ -f "$repo_root/tests/upstream-release-ignore.txt" ]; then
	sed 's/#.*//; s/^[	 ]*//; s/[	 ]*$//; /^[	 ]*$/d' "$repo_root/tests/upstream-release-ignore.txt" |
		LC_ALL=C sort -u > "$ignored_versions"
else
	: > "$ignored_versions"
fi

comm -23 "$upstream_versions" "$known_versions" |
	comm -23 - "$ignored_versions" > "$candidate_versions"
: > "$missing_versions"
: > "$skipped_versions"

has_enterprise_linux_payload() {
	release_index=$1

	sed -n 's/.*href="\([^"]*\)".*/\1/p' "$release_index" |
		grep -E '^(rhel|rocky|almalinux|ol|centos)(8|9|10)([./-]|/|$)' >/dev/null
}

has_source_rpm_payload() {
	version=$1
	release_index=$2

	if curl -fsSL "$upstream_url/$version/SRPMS/" >/dev/null 2>&1; then
		return 0
	fi

	grep -F "MLNX_OFED_SRC-$version.tgz" "$release_index" >/dev/null
}

while IFS= read -r version; do
	[ -n "$version" ] || continue

	release_index=$work_root/$version.index
	if ! curl -fsSL "$upstream_url/$version/" -o "$release_index"; then
		echo "$version: unable to read release index" >> "$skipped_versions"
		continue
	fi

	if ! has_enterprise_linux_payload "$release_index"; then
		echo "$version: no Enterprise Linux 8/9/10 payload" >> "$skipped_versions"
		continue
	fi

	if ! has_source_rpm_payload "$version" "$release_index"; then
		echo "$version: no SRPMS or standard source bundle" >> "$skipped_versions"
		continue
	fi

	echo "$version" >> "$missing_versions"
done < "$candidate_versions"

if [ -s "$missing_versions" ]; then
	cat "$missing_versions"
	exit 1
fi

if [ "${CHECK_UPSTREAM_VERBOSE:-0}" = 1 ] && [ -s "$skipped_versions" ]; then
	echo "Ignored upstream release directories:" >&2
	cat "$skipped_versions" >&2
fi

echo "No unsupported Enterprise Linux MLNX_OFED releases detected."
