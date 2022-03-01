postgresql_version="$1"

script_dir="$(dirname "${BASH_SOURCE[0]}")"

# shellcheck source=test/ci/setup-postgresql.bash
. "${script_dir}/setup-postgresql.bash" "$postgresql_version"

package_name="postgresql-${postgresql_version}-tableversion"
apt-get --assume-yes install "$package_name"
# shellcheck disable=SC2034
installed_package_version="$(dpkg-query --showformat='${Version}' --show "$package_name" | cut --delimiter=- --fields=1)"
