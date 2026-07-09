FROM almalinux:10.1

RUN groupadd --gid 1000 docker \
 && useradd --uid 1000 --gid 1000 --groups docker docker \
 && usermod -L docker

# PostgreSQL client comes from the PGDG repo: the AlmaLinux 10 AppStream
# `postgresql` package is 16.x, and pg_dump refuses to dump servers NEWER than
# itself — the CNPG clusters run PG 18. PGDG installs to /usr/pgsql-18/bin
# (prepended to PATH below).
RUN dnf update -y \
 && dnf install -y \
    bind-utils \
    procps-ng \
    findutils \
    zip unzip \
    zstd \
    jq \
    openssl \
 && dnf install -y \
    "https://download.postgresql.org/pub/repos/yum/reporpms/EL-10-x86_64/pgdg-redhat-repo-latest.noarch.rpm" \
 && dnf install -y \
    postgresql18 \
    mariadb \
 && dnf clean all \
 && rm -rf /var/cache/dnf /var/cache/yum

ENV PATH="/usr/pgsql-18/bin:${PATH}"

RUN cd /tmp \
 && curl -L "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip \
 && unzip awscliv2.zip \
 && ./aws/install \
 && rm -rf /tmp/*

RUN mkdir -p /snapshot \
 && chown -R docker:docker /snapshot

USER docker
WORKDIR /app

COPY --chown=docker:docker db-snapshot.sh /app/

CMD /app/db-snapshot.sh
