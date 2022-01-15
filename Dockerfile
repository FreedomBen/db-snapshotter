FROM almalinux:8

RUN groupadd --gid 1000 docker \
 && useradd --uid 1000 --gid 1000 --groups docker docker \
 && usermod -L docker

RUN dnf update -y \
 && dnf install -y \
    bind-utils \
    procps-ng \
    findutils \
    zip unzip \
    zstd \
    jq \
 && dnf module enable -y postgresql:12 \
 && dnf module enable -y mysql:8.0 \
 && dnf install -y \
    postgresql \
    mariadb \
 && dnf clean all \
 && rm -rf /var/cache/dnf /var/cache/yum

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
