# mlnxofed-patch

Shell script to patch MLNX OFED to add back support for MLX4 and EFA

## Use cases

This script has proven to be useful if you're maintaining systems like:
* HPC cluster with [OpenHPC](http://www.openhpc.community)
* [Red Hat Virtualization](https://www.redhat.com/technologies/virtualization/enterprise-virtualization)
and [oVirt](https://www.ovirt.org) with Openvswitch

If you have an additional use case please update this documentation with a Pull Request.

## Requirements:
* Enterprise Linux 8 or 9
  * Red Hat Enterprise Linux (RHEL)
  * Oracle Linux
  * Rocky Linux
  * Alma Linux
  * CentOS

* Enterprise Linux 8
  * CodeReady Builder / PowerTools repositories must be enabled
* Enterprise Linux 9
  * CRB must be enabled
  * EPEL is required for `pandoc`
* root privileges are needed for installation

## Supported MLNX OFED releases

| Series | Releases |
| --- | --- |
| 25.01 | `25.01-0.6.0.0` |
| 24.10 | `24.10-4.1.4.0`<br>`24.10-3.2.5.0`<br>`24.10-2.1.8.0`<br>`24.10-1.1.4.0.105`<br>`24.10-1.1.4.0`<br>`24.10-0.7.0.0`<br>`24.10-0.6.8.1`<br>`24.10-0.6.8.0` |
| 24.07 | `24.07-0.6.1.0`<br>`24.07-0.6.0.0` |
| 24.04 | `24.04-0.7.0.0`<br>`24.04-0.6.6.0`<br>`24.04-0.6.5.0` |
| 24.01 | `24.01-0.3.3.1` |
| 23.10 | `23.10-6.1.6.1`<br>`23.10-4.0.9.1`<br>`23.10-3.2.2.0`<br>`23.10-2.1.3.1.201`<br>`23.10-2.1.3.1`<br>`23.10-1.1.9.0`<br>`23.10-0.5.5.0` |
| 23.07 | `23.07-0.5.1.2`<br>`23.07-0.5.0.0` |
| 23.04 | `23.04-1.1.3.0`<br>`23.04-0.5.3.3` |
| 5.9 | `5.9-0.5.6.0.127`<br>`5.9-0.5.6.0.125`<br>`5.9-0.5.6.0` |
| 5.8 | `5.8-7.0.6.1`<br>`5.8-6.0.4.2`<br>`5.8-5.1.1.2`<br>`5.8-4.1.5.0`<br>`5.8-3.0.7.0.101`<br>`5.8-3.0.7.0`<br>`5.8-2.0.3.0`<br>`5.8-1.1.2.1`<br>`5.8-1.0.1.1` |
| 5.7 | `5.7-1.0.2.0` |
| 5.6 | `5.6-2.0.9.0`<br>`5.6-1.0.3.3` |
| 5.5 | `5.5-1.0.3.2` |
| 5.4 | `5.4-3.7.5.0`<br>`5.4-3.6.8.1`<br>`5.4-3.5.8.0`<br>`5.4-3.4.0.0`<br>`5.4-3.2.7.2.3`<br>`5.4-3.1.0.0`<br>`5.4-3.0.3.0`<br>`5.4-2.4.1.3`<br>`5.4-1.0.3.0` |
| 4.9 | `4.9-7.1.0.0`<br>`4.9-6.0.6.0`<br>`4.9-5.1.0.0`<br>`4.9-4.1.7.0`<br>`4.9-4.0.8.0`<br>`4.9-3.1.5.0`<br>`4.9-2.2.6.0`<br>`4.9-2.2.4.0`<br>`4.9-0.1.7.0` |

Debian-only or Ubuntu-only public drops are not listed because this script rebuilds RPM source packages.

## Usage:

Just run `patch-mlnxofed.sh` on a machine where MLNX OFED is already installed,
and you should be fine.

The script will execute `dnf` to install the new packages, but it's up to you to
install it or not. The resulting RPMs will be available by default on 
`PATCHED-MLNX-OFED` directory inside `$HOME`

## Verification

You can verify expected source markers and patched output lines against upstream
`rdma-core` source RPMs with:

`tests/verify-releases.sh 25.01-0.6.0.0 24.10-4.1.4.0 24.04-0.6.5.0 23.04-0.5.3.3 5.8-7.0.6.1`

# Open Source Apache License

This shell script is made available under the Apache License, Version 2.0:
https://www.apache.org/licenses/LICENSE-2.0
