#!/bin/bash

# Based on install_hawq_toolchain.bash in Pivotal-DataFabric/ci-infrastructure repo

set -euxo pipefail

setup_ssh_for_user() {
  local user="${1}"
  local home_dir
  home_dir=$(eval echo "~${user}")

  mkdir -p "${home_dir}"/.ssh
  touch "${home_dir}/.ssh/authorized_keys" "${home_dir}/.ssh/known_hosts" "${home_dir}/.ssh/config"
  ssh-keygen -t rsa -N "" -f "${home_dir}/.ssh/id_rsa"
  cat "${home_dir}/.ssh/id_rsa.pub" >> "${home_dir}/.ssh/authorized_keys"
  chmod 0600 "${home_dir}/.ssh/authorized_keys"
  chown -R "${user}" "${home_dir}/.ssh"
}

ssh_keyscan_for_user() {
  local user="${1}"
  local home_dir
  home_dir=$(eval echo "~${user}")

  {
    ssh-keyscan localhost
    ssh-keyscan 0.0.0.0
    ssh-keyscan github.com
  } >> "${home_dir}/.ssh/known_hosts"
}

transfer_ownership() {
  chown -R gpadmin:gpadmin gpdb_src
  chown -R gpadmin:gpadmin /usr/local/greenplum-db-devel
  chown -R gpadmin:gpadmin /home/gpadmin
}

setup_gpadmin_user_on_centos() {
  /usr/sbin/useradd gpadmin #by default, makes a gpadmin group for this user
  echo -e "password\npassword" | passwd gpadmin
  groupadd supergroup
  usermod -a -G supergroup gpadmin
  setup_ssh_for_user gpadmin
  transfer_ownership
}

setup_gpadmin_user_on_sles() {
  /usr/sbin/useradd gpadmin
  groupadd gpadmin
  usermod -A gpadmin gpadmin
  echo -e "password\npassword" | passwd gpadmin
  groupadd supergroup
  usermod -A supergroup gpadmin
  setup_ssh_for_user gpadmin
  transfer_ownership
}

setup_sshd() {
  if [ ! "$TEST_OS" = 'ubuntu' ]; then
    test -e /etc/ssh/ssh_host_key || ssh-keygen -f /etc/ssh/ssh_host_key -N '' -t rsa1
  fi
  test -e /etc/ssh/ssh_host_rsa_key || ssh-keygen -f /etc/ssh/ssh_host_rsa_key -N '' -t rsa
  test -e /etc/ssh/ssh_host_dsa_key || ssh-keygen -f /etc/ssh/ssh_host_dsa_key -N '' -t dsa

  # For Centos 7, disable looking for host key types that older Centos versions don't support.
  sed -ri 's@^HostKey /etc/ssh/ssh_host_ecdsa_key$@#&@' /etc/ssh/sshd_config
  sed -ri 's@^HostKey /etc/ssh/ssh_host_ed25519_key$@#&@' /etc/ssh/sshd_config

  # See https://gist.github.com/gasi/5691565
  sed -ri 's/UsePAM yes/UsePAM no/g' /etc/ssh/sshd_config
  # Disable password authentication so builds never hang given bad keys
  sed -ri 's/PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config

  setup_ssh_for_user root

  if [ "$TEST_OS" = 'ubuntu' ]; then
    mkdir -p /var/run/sshd
    chmod 0755 /var/run/sshd
  fi

  /usr/sbin/sshd

  ssh_keyscan_for_user root
  ssh_keyscan_for_user gpadmin
}

_main() {
  TEST_OS="$1"

  if [ "$TEST_OS" = "centos" ]; then
    setup_gpadmin_user_on_centos
  elif [ "$TEST_OS" = "sles" ]; then
    setup_gpadmin_user_on_sles
  fi
  setup_sshd
}

_main "$@"
