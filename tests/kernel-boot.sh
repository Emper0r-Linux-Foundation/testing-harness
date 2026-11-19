#!/bin/sh
# Run inside the booted test VM. Exits non-zero if a baseline check fails.
# Usage: kernel-boot.sh [--hardened]

set -u

hardened=0
[ "${1:-}" = "--hardened" ] && hardened=1

fails=0
checks=0

pass() {
	checks=$((checks + 1))
	printf 'PASS  %s\n' "$1"
}

fail() {
	checks=$((checks + 1))
	fails=$((fails + 1))
	printf 'FAIL  %s\n' "$1"
}

check_eq() {
	key=$1
	expected=$2
	actual=$(sysctl -n "$key" 2>/dev/null || true)
	[ "$actual" = "$expected" ] &&
		pass "$key = $expected" ||
		fail "$key = ${actual:-<missing>} (expected $expected)"
}

check_contains() {
	file=$1
	needle=$2
	if [ ! -r "$file" ]; then
		fail "$file is not readable"
		return
	fi
	grep -q -- "$needle" "$file" &&
		pass "$file contains $needle" ||
		fail "$file does not contain $needle"
}

check_absent() {
	path=$1
	[ ! -e "$path" ] && pass "$path is absent" || fail "$path exists"
}

version=$(uname -r)
case "$version" in
*-emperor*) pass "uname -r = $version" ;;
*) fail "uname -r = $version (missing -emperor)" ;;
esac

check_contains /proc/cmdline "mitigations=auto"
check_contains /proc/cmdline "lsm="
check_contains /proc/cmdline "module.sig_enforce=1"

check_eq kernel.kptr_restrict 1
check_eq kernel.dmesg_restrict 1
check_eq kernel.perf_event_paranoid 2
check_eq kernel.yama.ptrace_scope 1
check_eq kernel.unprivileged_bpf_disabled 2
check_eq kernel.randomize_va_space 2
check_eq vm.mmap_min_addr 65536
check_eq vm.mmap_rnd_bits 32
check_eq fs.protected_hardlinks 1
check_eq fs.protected_symlinks 1
check_eq fs.protected_fifos 2
check_eq fs.protected_regular 2
check_eq net.core.bpf_jit_harden 2
check_eq net.ipv4.conf.all.rp_filter 1
check_eq net.ipv4.tcp_syncookies 1
check_eq dev.tty.ldisc_autoload 0

for lsm in landlock lockdown yama apparmor; do
	check_contains /sys/kernel/security/lsm "$lsm"
done
if [ -r /sys/kernel/security/lockdown ]; then
	pass "/sys/kernel/security/lockdown is readable"
else
	fail "/sys/kernel/security/lockdown is not readable"
fi

if [ -r /sys/module/module/parameters/sig_enforce ]; then
	sig=$(cat /sys/module/module/parameters/sig_enforce 2>/dev/null || true)
	[ "$sig" = "Y" ] &&
		pass "module.sig_enforce = Y" ||
		fail "module.sig_enforce = ${sig:-<missing>} (expected Y)"
else
	fail "module signing parameter is missing"
fi

check_absent /proc/kcore

if [ "$hardened" -eq 1 ]; then
	check_eq kernel.kptr_restrict 2
	check_eq kernel.perf_event_paranoid 3
	check_eq kernel.kexec_load_disabled 1
	check_eq kernel.sysrq 0
	check_eq user.max_user_namespaces 0
	check_eq kernel.io_uring_disabled 2

	if command -v unshare >/dev/null 2>&1; then
		if unshare -Ur true >/dev/null 2>&1; then
			fail "unprivileged user namespaces still work"
		else
			pass "unprivileged user namespaces are blocked"
		fi
	fi
else
	if command -v unshare >/dev/null 2>&1; then
		if unshare -Ur true >/dev/null 2>&1; then
			pass "unprivileged user namespaces work"
		else
			fail "unprivileged user namespaces are blocked"
		fi
	fi
fi

if [ "$(id -u)" -eq 0 ] && command -v setpriv >/dev/null 2>&1; then
	if setpriv --reuid=65534 --regid=65534 --clear-groups dmesg >/dev/null 2>&1; then
		fail "unprivileged dmesg is allowed"
	else
		pass "unprivileged dmesg is blocked"
	fi
fi

printf '\n%d checks, %d failure(s)\n' "$checks" "$fails"
[ "$fails" -eq 0 ]
