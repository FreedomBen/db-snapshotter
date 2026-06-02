#!/usr/bin/env bats

load test_helper

setup() {
  setup_test_env
  export DB_TYPE="postgres"
  source_script
  # backup-postgres assumes the caller cd'd into the snapshot dir (main does).
  cd "${TEST_SNAPSHOT}"
}

@test "backup-postgres invokes pg_dump with target db, --inserts, -U, -h, -p" {
  run backup-postgres
  [ "${status}" -eq 0 ]

  local args
  args="$(stub_args pg_dump)"
  [[ "${args}" == *"testdb"* ]]
  [[ "${args}" == *"--inserts"* ]]
  [[ "${args}" == *"-U testuser"* ]]
  [[ "${args}" == *"-h db.test"* ]]
  [[ "${args}" == *"-p 5432"* ]]
}

@test "backup-postgres exports PGPASSWORD for pg_dump" {
  run backup-postgres
  [ "${status}" -eq 0 ]
  [ "$(stub_env_value pg_dump PGPASSWORD)" = "testpass" ]
}

@test "backup-postgres does not place the password on the command line" {
  run backup-postgres
  [ "${status}" -eq 0 ]

  local args
  args="$(stub_args pg_dump)"
  [[ "${args}" != *"testpass"* ]]
}

@test "backup-postgres compresses with zstd -T0 -19 --rm" {
  run backup-postgres
  [ "${status}" -eq 0 ]

  local args
  args="$(stub_args zstd)"
  [[ "${args}" == *"-T0"* ]]
  [[ "${args}" == *"-19"* ]]
  [[ "${args}" == *"--rm"* ]]
}

@test "backup-postgres produces filename <service>_<db>_<timestamp>-pgsql.sql.zst" {
  run backup-postgres
  [ "${status}" -eq 0 ]

  local args
  args="$(stub_args aws)"
  [[ "${args}" =~ testsvc_testdb_[0-9-]+-pgsql\.sql\.zst ]]
}

@test "backup-postgres uploads to s3://<bucket>/<prefix>/<file>" {
  export BUCKET_NAME="my-bucket"
  export PREFIX="hourly"
  run backup-postgres
  [ "${status}" -eq 0 ]

  local args
  args="$(stub_args aws)"
  [[ "${args}" == *"s3://my-bucket/hourly/"* ]]
  [[ "${args}" == *"-pgsql.sql.zst"* ]]
}

@test "backup-postgres encrypts when ENCRYPTION_ENABLED=true" {
  export ENCRYPTION_ENABLED="true"
  export ENCRYPTION_KEY="key"
  run backup-postgres
  [ "${status}" -eq 0 ]
  stub_called openssl

  local args
  args="$(stub_args aws)"
  [[ "${args}" == *".sql.zst.enc"* ]]
}

@test "backup-postgres does not encrypt when ENCRYPTION_ENABLED=false" {
  export ENCRYPTION_ENABLED="false"
  run backup-postgres
  [ "${status}" -eq 0 ]
  [ ! -f "${STUB_LOG}/openssl.args" ]

  local args
  args="$(stub_args aws)"
  [[ "${args}" != *".enc"* ]]
}

@test "backup-postgres dies on pg_dump failure with kubectl logs hint" {
  make_stub pg_dump 1
  run backup-postgres
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"pg_dump exited with status"* ]]
  [[ "${output}" == *"kubectl logs test-pod -n test-ns"* ]]
}

@test "backup-postgres announces dump start via slack_info when token set" {
  export SLACK_API_TOKEN="xoxp-test"
  export SLACK_CHANNEL_INFO="#info"
  run backup-postgres
  [ "${status}" -eq 0 ]

  local args
  args="$(stub_args curl)"
  [[ "${args}" == *"channel=#info"* ]]
  [[ "${args}" == *"Beginning dump of database 'testdb'"* ]]
}
