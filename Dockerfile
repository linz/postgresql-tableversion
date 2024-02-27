ARG RELEASE
FROM ubuntu:${RELEASE}
ARG RELEASE

ENV TZ=Pacific/Auckland

SHELL ["/bin/bash", "-o", "errexit", "-o", "nounset", "-o", "pipefail", "-O", "failglob", "-O", "inherit_errexit", "-c"]

# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get --assume-yes install --no-install-recommends \
        build-essential \
        libmodule-build-perl \
        ca-certificates \
        lsb-release \
        curl \
        vim \
        git \
        gnupg \
        make \
        jq \
    && rm -rf /var/lib/apt/lists/*

# Enable PostgreSQL package repository
ARG PG_VERSION=15
RUN curl https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
RUN echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
# hadolint ignore=DL3008
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get -y install --no-install-recommends postgresql-${PG_VERSION} \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Trust postgres user connections
RUN sed -i -e'/^local\s\+all\s\+postgres\s\+peer$/ s/peer/trust/' /etc/postgresql/${PG_VERSION}/main/pg_hba.conf

# Install pgTap and pg_prove
# hadolint ignore=DL3003
RUN git clone https://github.com/theory/pgtap.git \
    && cd pgtap \
    && make \
    && make install \
    && make clean
# hadolint ignore=DL3003
RUN git clone https://github.com/theory/tap-parser-sourcehandler-pgtap.git \
    && cd tap-parser-sourcehandler-pgtap \
    && perl Build.PL \
    && ./Build install

# Enable LINZ package repository
RUN curl -s https://packagecloud.io/install/repositories/linz/prod/script.deb.sh | bash

# hadolint ignore=DL3001
RUN service postgresql start \
    && su --command='createuser --superuser root' postgres \
    && service postgresql stop

ENTRYPOINT ["/bin/sh", "-c" , "service postgresql start && /bin/bash"]

WORKDIR /src
