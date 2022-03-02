export DEBIAN_FRONTEND=noninteractive

# Allow PostgreSQL service to start
set +o noclobber
echo exit 0 > /usr/sbin/policy-rc.d
set -o noclobber

apt-get update
# shellcheck disable=SC2154
apt-get --assume-yes install "postgresql-${postgresql_version}-pgtap" "postgresql-server-dev-${postgresql_version}"

su --command='createuser --superuser root' postgres
