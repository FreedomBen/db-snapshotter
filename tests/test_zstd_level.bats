#!/usr/bin/env bats

load test_helper

setup() {
  setup_test_env
  source_script
}

@test "verify_zstd_level passes on the default level" {
  run verify_zstd_level
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"zstd compression level is 19"* ]]
}

@test "verify_zstd_level passes on a custom in-range level" {
  export ZSTD_LEVEL=10
  run verify_zstd_level
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"zstd compression level is 10"* ]]
}

@test "verify_zstd_level dies on a non-numeric level" {
  export ZSTD_LEVEL="fast"
  run verify_zstd_level
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"not a positive integer"* ]]
}

@test "verify_zstd_level dies on an empty level" {
  export ZSTD_LEVEL=""
  run verify_zstd_level
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"not a positive integer"* ]]
}

@test "verify_zstd_level dies on a negative level" {
  export ZSTD_LEVEL="-5"
  run verify_zstd_level
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"not a positive integer"* ]]
}

@test "verify_zstd_level dies on level 0" {
  export ZSTD_LEVEL=0
  run verify_zstd_level
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"out of range"* ]]
}

@test "verify_zstd_level dies on level 20" {
  export ZSTD_LEVEL=20
  run verify_zstd_level
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"out of range"* ]]
}
