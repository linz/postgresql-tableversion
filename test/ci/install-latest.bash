# shellcheck source=test/ci/setup-postgresql.bash disable=SC2154
. "${script_dir}/setup-postgresql.bash"

package_name="postgresql-${postgresql_version}-tableversion"
readonly package_name

apt-get --assume-yes install "$package_name"
installed_package_version="$(dpkg-query --showformat='${Version}' --show "$package_name" | cut --delimiter=- --fields=1)"
# shellcheck disable=SC2034
readonly installed_package_version

su --command='psql --command="CREATE EXTENSION table_version"' postgres
