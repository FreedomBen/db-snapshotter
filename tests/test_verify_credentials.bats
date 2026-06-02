#!/usr/bin/env bats

load test_helper

setup() {
  setup_test_env
  source_script
}

@test "verify_credentials dies when AWS_SECRET_ACCESS_KEY is unset" {
  unset AWS_SECRET_ACCESS_KEY
  run verify_credentials
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"AWS_SECRET_ACCESS_KEY is not set"* ]]
}

@test "verify_credentials dies when AWS_ACCESS_KEY_ID is unset" {
  unset AWS_ACCESS_KEY_ID
  run verify_credentials
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"AWS_ACCESS_KEY_ID is not set"* ]]
}

@test "verify_credentials warns but does not die when AWS_ENDPOINT_URL is unset" {
  unset AWS_ENDPOINT_URL
  run verify_credentials
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"AWS_ENDPOINT_URL is not set"* ]]
}

@test "verify_credentials dies when encryption enabled but ENCRYPTION_KEY unset" {
  export ENCRYPTION_ENABLED="true"
  unset ENCRYPTION_KEY
  run verify_credentials
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"ENCRYPTION_KEY is not set"* ]]
}

@test "verify_credentials passes when encryption enabled and ENCRYPTION_KEY is set" {
  export ENCRYPTION_ENABLED="true"
  export ENCRYPTION_KEY="abc123"
  run verify_credentials
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Backup encryption is enabled"* ]]
}

@test "verify_credentials passes with encryption disabled" {
  export ENCRYPTION_ENABLED="false"
  run verify_credentials
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Backup encryption is disabled"* ]]
}

@test "verify_credentials defaults encryption to enabled when ENCRYPTION_ENABLED is unset" {
  unset ENCRYPTION_ENABLED
  unset ENCRYPTION_KEY
  run verify_credentials
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"ENCRYPTION_KEY is not set"* ]]
}
