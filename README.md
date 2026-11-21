# testing-harness
Automated VM boot tests and CI checks to verify new ISOs and packages don't break existing installs.

## Kernel boot checks

`tests/kernel-boot.sh` runs inside the booted VM and exits non-zero on failure:

```sh
./tests/kernel-boot.sh             # baseline profile
./tests/kernel-boot.sh --hardened  # hardened sysctl profile
```

The baseline checks the `-emperor` release suffix, command line, LSM list,
module-signature enforcement, `/proc/kcore` removal, and the expected sysctl
values. `--hardened` additionally checks kexec/SysRq/user-namespace/io_uring
restrictions. It expects the baseline sysctl drop-in and bootloader command
line to be installed; `unshare` and `setpriv` tests are skipped when the tools
are unavailable.
