#!/usr/bin/env bats

load test_helper

setup() {
  setup_test_env
  source_script
}

@test "runtime_seconds returns a non-negative integer" {
  run runtime_seconds
  [ "${status}" -eq 0 ]
  [[ "${output}" =~ ^[0-9]+$ ]]
}

@test "slack_username defaults to 'DB Snapshotter for <SERVICE_NAME>'" {
  unset SLACK_USERNAME
  export SERVICE_NAME="my-svc"
  run slack_username
  [ "${status}" -eq 0 ]
  [ "${output}" = "DB Snapshotter for my-svc" ]
}

@test "slack_username returns SLACK_USERNAME when set" {
  export SLACK_USERNAME="Custom"
  run slack_username
  [ "${output}" = "Custom" ]
}

@test "slack_icon_emoji defaults to :database:" {
  unset SLACK_ICON_EMOJI
  run slack_icon_emoji
  [ "${output}" = ":database:" ]
}

@test "slack_icon_emoji returns SLACK_ICON_EMOJI when set" {
  export SLACK_ICON_EMOJI=":fire:"
  run slack_icon_emoji
  [ "${output}" = ":fire:" ]
}

@test "log emits [LOG] prefix" {
  run log "hello"
  [[ "${output}" == *"[LOG]"* ]]
  [[ "${output}" == *"hello"* ]]
}

@test "info emits [INFO] prefix" {
  run info "hello"
  [[ "${output}" == *"[INFO]"* ]]
  [[ "${output}" == *"hello"* ]]
}

@test "warn emits [WARN] prefix" {
  run warn "hello"
  [[ "${output}" == *"[WARN]"* ]]
  [[ "${output}" == *"hello"* ]]
}

@test "debug emits [DEBUG] prefix" {
  run debug "hello"
  [[ "${output}" == *"[DEBUG]"* ]]
  [[ "${output}" == *"hello"* ]]
}

@test "die prints [FATAL], calls slack_error, exits 1" {
  export SLACK_API_TOKEN="xoxp-test"
  export SLACK_CHANNEL_ERROR="#err"
  export TARGET_DATABASE="testdb"
  run die "boom"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"[FATAL]"* ]]
  [[ "${output}" == *"boom"* ]]
  stub_called curl
  local args
  args="$(stub_args curl)"
  [[ "${args}" == *"channel=#err"* ]]
  [[ "${args}" == *"testdb"* ]]
}

@test "file_size returns a non-empty string from du" {
  local f="${BATS_TEST_TMPDIR}/foo"
  echo "abc" > "${f}"
  run file_size "${f}"
  [ "${status}" -eq 0 ]
  [ -n "${output}" ]
}
