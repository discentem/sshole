# Intentionally vulnerable, isolated PoC. BASE defaults to alpine:latest and
# can be overridden to test another musl-based Alpine image. The current Alpine
# APKINDEX selects the fixed OpenSSH package, so download the official v3.24
# pre-fix 10.3_p1-r1 APKs and verify their SHA-256 digests instead. The stock
# sshd configuration is retained; alice has "*" (key-only), bob has a password.
ARG BASE=alpine:latest
FROM ${BASE}
ARG ALPINE_MAIN=https://dl-cdn.alpinelinux.org/alpine/v3.24/main/x86_64
RUN set -eux; \
 wget -q "$ALPINE_MAIN/openssh-keygen-10.3_p1-r1.apk" -O /tmp/keygen.apk; \
 wget -q "$ALPINE_MAIN/openssh-server-common-10.3_p1-r1.apk" -O /tmp/common.apk; \
 wget -q "$ALPINE_MAIN/openssh-server-10.3_p1-r1.apk" -O /tmp/server.apk; \
 echo 'a7a197dd781fd25d127fe7815db3d69130f0772655f421b4a88c7e4f7bb2ecf7  /tmp/keygen.apk' | sha256sum -c -; \
 echo 'd91b68c19d02f61587eb3e6b6b5a30c9658f22b655e412adbd25eddd503229bd  /tmp/common.apk' | sha256sum -c -; \
 echo '2818d1c4ba1cc279e226632aceea3ada2c7652977fce364f75c0d2ad058ea57f  /tmp/server.apk' | sha256sum -c -; \
 apk add --no-cache --allow-untrusted /tmp/keygen.apk /tmp/common.apk /tmp/server.apk; \
 rm /tmp/keygen.apk /tmp/common.apk /tmp/server.apk; \
 ssh-keygen -A \
 && adduser -D -s /bin/sh alice && adduser -D -s /bin/sh bob \
 && echo 'bob:BobPass-123' | chpasswd \
 && sed -i 's/^alice:[^:]*:/alice:*:/' /etc/shadow
EXPOSE 22
CMD ["/usr/sbin/sshd", "-D", "-e"]
