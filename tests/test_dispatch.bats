#!/usr/bin/env bats

load test_helper

setup() {
  setup_test_env
}

@test "main dispatches to backup-postgres when DB_TYPE=postgres" {
  export DB_TYPE="postgres"
  source_script
  run main
  [ "${status}" -eq 0 ]
  stub_called pg_dump
  ! stub_called mysqldump
}

@test "main dispatches to backup-postgres for any DB_TYPE starting with 'p'" {
  export DB_TYPE="psql"
  source_script
  run main
  [ "${status}" -eq 0 ]
  stub_called pg_dump
}

@test "main dispatches to backup-mysql when DB_TYPE=mysql" {
  export DB_TYPE="mysql"
  source_script
  run main
  [ "${status}" -eq 0 ]
  stub_called mysqldump
  ! stub_called pg_dump
}

@test "main dispatches to backup-mysql for any DB_TYPE starting with 'm' (mongodb routes to MySQL)" {
  # Documents the current first-letter dispatch: mongodb/mssql silently route
  # to mysql. If you add a new engine, update this test and the dispatch.
  export DB_TYPE="mongodb"
  source_script
  run main
  [ "${status}" -eq 0 ]
  stub_called mysqldump
}

@test "main dies on unknown DB_TYPE" {
  export DB_TYPE="redis"
  source_script
  run main
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Unknown DB_TYPE"* ]]
}

@test "main dies on empty DB_TYPE" {
  export DB_TYPE=""
  source_script
  run main
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Unknown DB_TYPE"* ]]
}

@test "main creates SNAPSHOT_DIR before dumping" {
  rm -rf "${TEST_SNAPSHOT}"
  export DB_TYPE="postgres"
  source_script
  run main
  [ "${status}" -eq 0 ]
  [ -d "${TEST_SNAPSHOT}" ]
}

@test "main fails fast when credentials are missing" {
  unset AWS_SECRET_ACCESS_KEY
  source_script
  run main
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"AWS_SECRET_ACCESS_KEY is not set"* ]]
  # Should not have reached pg_dump
  ! stub_called pg_dump
  ! stub_called mysqldump
}
