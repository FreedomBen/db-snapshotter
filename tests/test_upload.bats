#!/usr/bin/env bats

load test_helper

setup() {
  setup_test_env
  source_script
}

@test "upload_file_to_bucket uses --endpoint-url when AWS_ENDPOINT_URL is set" {
  export AWS_ENDPOINT_URL="https://s3.test.io"
  export BUCKET_NAME="mybucket"
  export PREFIX="daily"
  run upload_file_to_bucket "foo.zst" "100K"
  [ "${status}" -eq 0 ]

  local args
  args="$(stub_args aws)"
  [[ "${args}" == *"--endpoint-url=https://s3.test.io"* ]]
  [[ "${args}" == *"foo.zst"* ]]
  [[ "${args}" == *"s3://mybucket/daily/foo.zst"* ]]
}

@test "upload_file_to_bucket omits --endpoint-url when AWS_ENDPOINT_URL is unset" {
  unset AWS_ENDPOINT_URL
  export BUCKET_NAME="mybucket"
  export PREFIX="daily"
  run upload_file_to_bucket "bar.zst" "1M"
  [ "${status}" -eq 0 ]

  local args
  args="$(stub_args aws)"
  [[ "${args}" != *"--endpoint-url"* ]]
  [[ "${args}" == *"s3://mybucket/daily/bar.zst"* ]]
}

@test "upload_file_to_bucket sends slack_success when aws s3 cp exits 0" {
  export SLACK_API_TOKEN="xoxp-test"
  export SLACK_CHANNEL_SUCCESS="#ok"
  export TARGET_DATABASE="testdb"
  run upload_file_to_bucket "foo.zst" "100K"
  [ "${status}" -eq 0 ]

  local args
  args="$(stub_args curl)"
  [[ "${args}" == *"channel=#ok"* ]]
  [[ "${args}" == *"succeeded"* ]]
  [[ "${args}" == *"testdb"* ]]
  [[ "${args}" == *"100K"* ]]
}

@test "upload_file_to_bucket sends slack_error and returns non-zero on aws failure" {
  make_stub aws 1
  export SLACK_API_TOKEN="xoxp-test"
  export SLACK_CHANNEL_ERROR="#err"
  export TARGET_DATABASE="testdb"
  run upload_file_to_bucket "foo.zst" "100K"
  [ "${status}" -ne 0 ]

  local args
  args="$(stub_args curl)"
  [[ "${args}" == *"channel=#err"* ]]
  [[ "${args}" == *"uploading to object storage failed"* ]]
  [[ "${args}" == *"kubectl logs test-pod -n test-ns"* ]]
}

@test "upload_file_to_bucket reads podname/namespace from PODINFO_DIR for failure message" {
  echo "alt-pod" > "${TEST_PODINFO}/podname"
  echo "alt-ns"  > "${TEST_PODINFO}/namespace"
  make_stub aws 1
  export SLACK_API_TOKEN="xoxp-test"
  export SLACK_CHANNEL_ERROR="#err"
  run upload_file_to_bucket "foo.zst" "100K"
  [ "${status}" -ne 0 ]

  local args
  args="$(stub_args curl)"
  [[ "${args}" == *"kubectl logs alt-pod -n alt-ns"* ]]
}
