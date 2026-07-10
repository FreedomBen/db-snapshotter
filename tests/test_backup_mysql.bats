#!/usr/bin/env bats

load test_helper

setup() {
  setup_test_env
  export DB_TYPE="mysql"
  source_script
  cd "${TEST_SNAPSHOT}"
}

@test "backup-mysql invokes mysqldump with target db, -h, -P, -u" {
  run backup-mysql
  [ "${status}" -eq 0 ]

  local args
  args="$(stub_args mysqldump)"
  [[ "${args}" == *"testdb"* ]]
  [[ "${args}" == *"-h db.test"* ]]
  [[ "${args}" == *"-P 5432"* ]]
  [[ "${args}" == *"-u testuser"* ]]
}

@test "backup-mysql passes the password via MYSQL_PWD env var (never on argv)" {
  run backup-mysql
  [ "${status}" -eq 0 ]

  local args
  args="$(stub_args mysqldump)"
  [[ "${args}" != *"--password"* ]]
  [[ "${args}" != *"testpass"* ]]
  [ "$(stub_env_value mysqldump MYSQL_PWD)" = "testpass" ]
}

@test "backup-mysql compresses with zstd -T0 -19 --rm by default" {
  run backup-mysql
  [ "${status}" -eq 0 ]

  local args
  args="$(stub_args zstd)"
  [[ "${args}" == *"-T0"* ]]
  [[ " ${args} " == *" -19 "* ]]
  [[ "${args}" == *"--rm"* ]]
}

@test "backup-mysql honors ZSTD_LEVEL" {
  export ZSTD_LEVEL=7
  run backup-mysql
  [ "${status}" -eq 0 ]

  local args
  args="$(stub_args zstd)"
  [[ " ${args} " == *" -7 "* ]]
  [[ " ${args} " != *" -19 "* ]]
}

@test "backup-mysql produces filename <service>_<db>_<timestamp>-mysql.sql.zst" {
  run backup-mysql
  [ "${status}" -eq 0 ]

  local args
  args="$(stub_args aws)"
  [[ "${args}" =~ testsvc_testdb_[0-9-]+-mysql\.sql\.zst ]]
}

@test "backup-mysql uploads to s3://<bucket>/<prefix>/<file>" {
  export BUCKET_NAME="my-bucket"
  export PREFIX="hourly"
  run backup-mysql
  [ "${status}" -eq 0 ]

  local args
  args="$(stub_args aws)"
  [[ "${args}" == *"s3://my-bucket/hourly/"* ]]
  [[ "${args}" == *"-mysql.sql.zst"* ]]
}

@test "backup-mysql encrypts when ENCRYPTION_ENABLED=true" {
  export ENCRYPTION_ENABLED="true"
  export ENCRYPTION_KEY="key"
  run backup-mysql
  [ "${status}" -eq 0 ]
  stub_called openssl

  local args
  args="$(stub_args aws)"
  [[ "${args}" == *".sql.zst.enc"* ]]
}

@test "backup-mysql does not encrypt when ENCRYPTION_ENABLED=false" {
  export ENCRYPTION_ENABLED="false"
  run backup-mysql
  [ "${status}" -eq 0 ]
  [ ! -f "${STUB_LOG}/openssl.args" ]

  local args
  args="$(stub_args aws)"
  [[ "${args}" != *".enc"* ]]
}

@test "backup-mysql dies on mysqldump failure with kubectl logs hint" {
  make_stub mysqldump 1
  run backup-mysql
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"mysqldump exited with status"* ]]
  [[ "${output}" == *"kubectl logs test-pod -n test-ns"* ]]
}

@test "backup-mysql announces dump start via slack_info when token set" {
  export SLACK_API_TOKEN="xoxp-test"
  export SLACK_CHANNEL_INFO="#info"
  run backup-mysql
  [ "${status}" -eq 0 ]

  local args
  args="$(stub_args curl)"
  [[ "${args}" == *"channel=#info"* ]]
  [[ "${args}" == *"Beginning dump of database 'testdb'"* ]]
}
