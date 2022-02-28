ARG RELEASE
FROM ubuntu:${RELEASE}
ARG RELEASE

SHELL ["/bin/bash", "-o", "errexit", "-o", "nounset", "-o", "pipefail", "-O", "failglob", "-O", "inherit_errexit", "-c"]

# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get --assume-yes install --no-install-recommends \
        ca-certificates \
        curl \
        git \
        gnupg \
        make \
        jq \
    && rm -rf /var/lib/apt/lists/*

# Enable PostgreSQL package repository
RUN curl https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
RUN echo "deb http://apt.postgresql.org/pub/repos/apt/ ${RELEASE}-pgdg main" > /etc/apt/sources.list.d/pgdg.list

# Enable LINZ package repository
RUN curl https://packagecloud.io/install/repositories/linz/prod/script.deb.sh > script.deb.sh \
    && chmod u+x script.deb.sh \
    && os=ubuntu dist=${RELEASE} ./script.deb.sh \
    && rm script.deb.sh

COPY . /src
WORKDIR /src
