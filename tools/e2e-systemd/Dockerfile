FROM debian:12
ENV container=docker DEBIAN_FRONTEND=noninteractive
RUN apt-get -o Acquire::Retries=5 update -qq \
 && apt-get -o Acquire::Retries=5 install -y -qq --no-install-recommends \
      systemd systemd-sysv dbus nginx cron curl ca-certificates \
      tar gzip python3 \
 && rm -rf /var/lib/apt/lists/*
# A container has no getty, and a failed getty is what leaves systemd in the
# "degraded" state that makes `systemctl is-system-running` fail. Mask it so the
# scripts under test see the same "running" system a real host reports.
RUN ln -sf /dev/null /etc/systemd/system/getty@tty1.service \
 && ln -sf /dev/null /etc/systemd/system/serial-getty@ttyS0.service
# The release asset is a copy of a real, dynamically linked system binary: the
# install flow verifies ELF magic and systemd has to execute it for real, so it
# must be a binary this image can actually run.
RUN mkdir -p /opt/fixtures && cp /usr/bin/tail /opt/fixtures/service-bin
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
