# mlnxofed-patch

Shell script to patch MLNX OFED to add back support for MLX4 and EFA

## Use cases

This script has proven to be useful if you're maintaining systems like:
* HPC cluster with [OpenHPC](http://www.openhpc.community)
* [Red Hat Virtualization](https://www.redhat.com/technologies/virtualization/enterprise-virtualization)
and [oVirt](https://www.ovirt.org) with Openvswitch

If you have an additional use case please update this documentation with a Pull Request.

## Requirements:
* Enterprise Linux 8
  * Red Hat Enterprise Linux (RHEL)
  * Oracle Linux
  * Rocky Linux
  * Alma Linux
  * CentOS


* Mellanox OFED
  * 5.5-1.0.3.2
  * 5.4-3.4.0.0
  * 5.4-3.2.7.2.3
  * 5.4-3.1.0.0
  * 5.4-3.0.3.0
  * 5.4-2.4.1.3
  * 5.4-1.0.3.0
  * 4.9-5.1.0.0
  * 4.9-4.1.7.0
  * 4.9-4.0.8.0
  * 4.9-3.1.5.0
  * 4.9-2.2.6.0
  * 4.9-2.2.4.0
  * 4.9-0.1.7.0

* CodeReady Builder / PowerTools repositories must be enabled 
* root privileges are needed for installation

## Usage:

Just run `patch-mlnxofed.sh` on a machine where MLNX OFED is already installed,
and you should be fine.

The script will execute `dnf` to install the new packages, but it's up to you to
install it or not. The resulting RPMs will be available by default on 
`PATCHED-MLNX-OFED` directory inside `$HOME`

# Open Source Apache License

This shell script is made available under the Apache License, Version 2.0:
https://www.apache.org/licenses/LICENSE-2.0
