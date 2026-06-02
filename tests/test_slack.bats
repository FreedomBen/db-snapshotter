#!/usr/bin/env bats

load test_helper

setup() {
  setup_test_env
  source_script
}

@test "send_slack_message is a no-op when SLACK_API_TOKEN is unset" {
  unset SLACK_API_TOKEN
  run send_slack_message "#ch" "hi"
  [ "${status}" -eq 0 ]
  [ ! -f "${STUB_LOG}/curl.args" ]
}

@test "send_slack_message calls Slack chat.postMessage with channel, text, and token" {
  export SLACK_API_TOKEN="xoxp-test"
  run send_slack_message "#ch" "hello world"
  [ "${status}" -eq 0 ]

  local args
  args="$(stub_args curl)"
  [[ "${args}" == *"channel=#ch"* ]]
  [[ "${args}" == *"text=hello world"* ]]
  [[ "${args}" == *"token=xoxp-test"* ]]
  [[ "${args}" == *"https://slack.com/api/chat.postMessage"* ]]
}

@test "send_slack_message includes default username and icon when not overridden" {
  export SLACK_API_TOKEN="xoxp-test"
  export SERVICE_NAME="acme"
  unset SLACK_USERNAME SLACK_ICON_EMOJI
  run send_slack_message "#ch" "hi"

  local args
  args="$(stub_args curl)"
  [[ "${args}" == *"username=DB Snapshotter for acme"* ]]
  [[ "${args}" == *"icon_emoji=:database:"* ]]
}

@test "send_slack_message honors SLACK_USERNAME and SLACK_ICON_EMOJI overrides" {
  export SLACK_API_TOKEN="xoxp-test"
  export SLACK_USERNAME="Custom Bot"
  export SLACK_ICON_EMOJI=":fire:"
  run send_slack_message "#ch" "hi"

  local args
  args="$(stub_args curl)"
  [[ "${args}" == *"username=Custom Bot"* ]]
  [[ "${args}" == *"icon_emoji=:fire:"* ]]
}

@test "slack_success posts to SLACK_CHANNEL_SUCCESS with :white_check_mark:" {
  export SLACK_API_TOKEN="xoxp-test"
  export SLACK_CHANNEL_SUCCESS="#ok"
  run slack_success "all good"
  local args
  args="$(stub_args curl)"
  [[ "${args}" == *"channel=#ok"* ]]
  [[ "${args}" == *":white_check_mark:"* ]]
  [[ "${args}" == *"all good"* ]]
}

@test "slack_error posts to SLACK_CHANNEL_ERROR with :x:" {
  export SLACK_API_TOKEN="xoxp-test"
  export SLACK_CHANNEL_ERROR="#err"
  run slack_error "kaboom"
  local args
  args="$(stub_args curl)"
  [[ "${args}" == *"channel=#err"* ]]
  [[ "${args}" == *":x:"* ]]
  [[ "${args}" == *"kaboom"* ]]
}

@test "slack_warning posts to SLACK_CHANNEL_WARNING with :warning:" {
  export SLACK_API_TOKEN="xoxp-test"
  export SLACK_CHANNEL_WARNING="#warn"
  run slack_warning "heads up"
  local args
  args="$(stub_args curl)"
  [[ "${args}" == *"channel=#warn"* ]]
  [[ "${args}" == *":warning:"* ]]
}

@test "slack_info posts to SLACK_CHANNEL_INFO with :information_source:" {
  export SLACK_API_TOKEN="xoxp-test"
  export SLACK_CHANNEL_INFO="#info"
  run slack_info "fyi"
  local args
  args="$(stub_args curl)"
  [[ "${args}" == *"channel=#info"* ]]
  [[ "${args}" == *":information_source:"* ]]
}

@test "slack_debug posts to SLACK_CHANNEL_DEBUG with :information_source:" {
  export SLACK_API_TOKEN="xoxp-test"
  export SLACK_CHANNEL_DEBUG="#dbg"
  run slack_debug "noise"
  local args
  args="$(stub_args curl)"
  [[ "${args}" == *"channel=#dbg"* ]]
  [[ "${args}" == *":information_source:"* ]]
}
