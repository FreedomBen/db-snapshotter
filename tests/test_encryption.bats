#!/usr/bin/env bats

load test_helper

setup() {
  setup_test_env
  source_script
}

@test "encryption_enabled defaults to true when unset" {
  unset ENCRYPTION_ENABLED
  run encryption_enabled
  [ "${status}" -eq 0 ]
}

@test "encryption_enabled is false for 'false'" {
  export ENCRYPTION_ENABLED="false"
  run encryption_enabled
  [ "${status}" -ne 0 ]
}

@test "encryption_enabled is false for 'FALSE'" {
  export ENCRYPTION_ENABLED="FALSE"
  run encryption_enabled
  [ "${status}" -ne 0 ]
}

@test "encryption_enabled is false for '0'" {
  export ENCRYPTION_ENABLED="0"
  run encryption_enabled
  [ "${status}" -ne 0 ]
}

@test "encryption_enabled is false for 'no'" {
  export ENCRYPTION_ENABLED="no"
  run encryption_enabled
  [ "${status}" -ne 0 ]
}

@test "encryption_enabled is false for 'off'" {
  export ENCRYPTION_ENABLED="off"
  run encryption_enabled
  [ "${status}" -ne 0 ]
}

@test "encryption_enabled is false for 'disabled'" {
  export ENCRYPTION_ENABLED="disabled"
  run encryption_enabled
  [ "${status}" -ne 0 ]
}

@test "encryption_enabled is true for 'true'" {
  export ENCRYPTION_ENABLED="true"
  run encryption_enabled
  [ "${status}" -eq 0 ]
}

@test "encryption_enabled is true for arbitrary truthy strings" {
  export ENCRYPTION_ENABLED="yes"
  run encryption_enabled
  [ "${status}" -eq 0 ]
}

@test "encrypt_file invokes openssl with AES-256-CBC + PBKDF2 + env-passed key" {
  local in_file="${BATS_TEST_TMPDIR}/test.sql.zst"
  local out_file="${BATS_TEST_TMPDIR}/test.sql.zst.enc"
  echo "fake compressed content" > "${in_file}"
  export ENCRYPTION_KEY="testkey"

  cd "${BATS_TEST_TMPDIR}"
  run encrypt_file "${in_file}" "${out_file}"
  [ "${status}" -eq 0 ]

  local args
  args="$(stub_args openssl)"
  [[ "${args}" == *"enc"* ]]
  [[ "${args}" == *"-aes-256-cbc"* ]]
  [[ "${args}" == *"-salt"* ]]
  [[ "${args}" == *"-pbkdf2"* ]]
  [[ "${args}" == *"-iter 100000"* ]]
  [[ "${args}" == *"-pass env:ENCRYPTION_KEY"* ]]
  [[ "${args}" == *"-in ${in_file}"* ]]
  [[ "${args}" == *"-out ${out_file}"* ]]
}

@test "encrypt_file passes ENCRYPTION_KEY via environment, not command line" {
  local in_file="${BATS_TEST_TMPDIR}/test.sql.zst"
  local out_file="${BATS_TEST_TMPDIR}/test.sql.zst.enc"
  echo "fake" > "${in_file}"
  export ENCRYPTION_KEY="super-secret-key-value"

  cd "${BATS_TEST_TMPDIR}"
  run encrypt_file "${in_file}" "${out_file}"
  [ "${status}" -eq 0 ]

  local args
  args="$(stub_args openssl)"
  # The literal key must never appear in argv
  [[ "${args}" != *"super-secret-key-value"* ]]
  # ...but it must be present in the env the stub saw
  [ "$(stub_env_value openssl ENCRYPTION_KEY)" = "super-secret-key-value" ]
}

@test "encrypt_file removes the unencrypted input on success" {
  local in_file="${BATS_TEST_TMPDIR}/test.sql.zst"
  local out_file="${BATS_TEST_TMPDIR}/test.sql.zst.enc"
  echo "fake" > "${in_file}"
  export ENCRYPTION_KEY="testkey"

  cd "${BATS_TEST_TMPDIR}"
  run encrypt_file "${in_file}" "${out_file}"
  [ "${status}" -eq 0 ]
  [ ! -f "${in_file}" ]
  [ -f "${out_file}" ]
}

@test "encrypt_file dies when openssl fails" {
  local in_file="${BATS_TEST_TMPDIR}/test.sql.zst"
  local out_file="${BATS_TEST_TMPDIR}/test.sql.zst.enc"
  echo "fake" > "${in_file}"
  export ENCRYPTION_KEY="testkey"
  make_stub openssl 1

  cd "${BATS_TEST_TMPDIR}"
  run encrypt_file "${in_file}" "${out_file}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"openssl encryption exited with status"* ]]
}
