#!/usr/bin/env bash
# Shared setup, stub framework, and assertion helpers for db-snapshot.sh tests.
#
# Each test sources this via `load test_helper`, then calls:
#   setup_test_env    - prepares stub PATH, snapshot dir, podinfo dir, default env
#   source_script     - sources db-snapshot.sh without invoking main()
#
# Stubs record their args (and full environment) under "${STUB_LOG}" so tests
# can assert on what arguments were passed and which env vars were exported.

SCRIPT_PATH="${BATS_TEST_DIRNAME}/../db-snapshot.sh"

# Prepare the per-test sandbox: stub PATH dir, snapshot dir, podinfo dir,
# stub log dir, default env vars, and a baseline of stubs.
setup_test_env() {
  TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  TEST_SNAPSHOT="${BATS_TEST_TMPDIR}/snapshot"
  TEST_PODINFO="${BATS_TEST_TMPDIR}/podinfo"
  STUB_LOG="${BATS_TEST_TMPDIR}/stub-logs"
  mkdir -p "${TEST_BIN}" "${TEST_SNAPSHOT}" "${TEST_PODINFO}" "${STUB_LOG}"

  export PATH="${TEST_BIN}:${PATH}"
  export STUB_LOG TEST_BIN TEST_SNAPSHOT TEST_PODINFO

  # Path overrides so the script doesn't touch /snapshot or /etc/podinfo.
  export SNAPSHOT_DIR="${TEST_SNAPSHOT}"
  export PODINFO_DIR="${TEST_PODINFO}"

  # Default credentials and config that satisfy verify_credentials.
  export DB_TYPE="postgres"
  export DB_HOSTNAME="db.test"
  export DB_PORT="5432"
  export DB_USERNAME="testuser"
  export DB_PASSWORD="testpass"
  export TARGET_DATABASE="testdb"
  export SERVICE_NAME="testsvc"
  export PREFIX="daily"
  export BUCKET_NAME="test-bucket"
  export AWS_ENDPOINT_URL="https://s3.test.invalid"
  export AWS_ACCESS_KEY_ID="AKIA-test"
  export AWS_SECRET_ACCESS_KEY="secret-test"

  # Tests opt in to encryption explicitly; default off keeps assertions simpler.
  export ENCRYPTION_ENABLED="false"
  unset ENCRYPTION_KEY

  # No Slack by default; individual tests set SLACK_API_TOKEN to enable it.
  unset SLACK_API_TOKEN
  unset SLACK_CHANNEL_DEBUG SLACK_CHANNEL_INFO SLACK_CHANNEL_WARNING
  unset SLACK_CHANNEL_ERROR SLACK_CHANNEL_SUCCESS
  unset SLACK_USERNAME SLACK_ICON_EMOJI

  # Populate podinfo files used by die() messages.
  echo "test-pod" > "${TEST_PODINFO}/podname"
  echo "test-ns"  > "${TEST_PODINFO}/namespace"

  # Default stubs. Individual tests can override by calling make_stub again.
  make_stub aws       0
  make_stub curl      0 "ok"
  make_stub pg_dump   0 "-- fake pg_dump"
  make_stub mysqldump 0 "-- fake mysqldump"
  make_stub zstd      0
  make_stub openssl   0
}

# make_stub <name> <exit_code> [stdout_text]
#
# Generates an executable stub under "${TEST_BIN}" that:
#   - appends its args (one line) to "${STUB_LOG}/<name>.args"
#   - writes a snapshot of `env` to "${STUB_LOG}/<name>.env"
#   - performs minimal side-effects for zstd/openssl so the script's downstream
#     filename juggling still works
#   - prints the optional stdout, then exits with the given code
make_stub() {
  local name="${1}"
  local exit_code="${2:-0}"
  local stdout="${3:-}"
  local path="${TEST_BIN}/${name}"

  cat > "${path}" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "${STUB_LOG}/${name}.args"
env > "${STUB_LOG}/${name}.env"
EOF

  case "${name}" in
    zstd)
      cat >> "${path}" <<'STUB'
# Locate the (non-flag) input file. Touch <input>.zst; honor --rm.
input=""
for arg in "$@"; do
  case "${arg}" in
    -*) ;;
    *) [ -f "${arg}" ] && input="${arg}" ;;
  esac
done
if [ -n "${input}" ]; then
  touch "${input}.zst"
  case " $* " in
    *' --rm '*) rm -f "${input}" ;;
  esac
fi
STUB
      ;;
    openssl)
      cat >> "${path}" <<'STUB'
# Parse -in/-out and produce the output file so the script can stat() it.
in_file=""
out_file=""
while [ $# -gt 0 ]; do
  case "${1}" in
    -in)  in_file="${2}";  shift 2 ;;
    -out) out_file="${2}"; shift 2 ;;
    *) shift ;;
  esac
done
if [ -n "${out_file}" ]; then
  if [ -n "${in_file}" ] && [ -f "${in_file}" ]; then
    cp "${in_file}" "${out_file}"
  else
    : > "${out_file}"
  fi
fi
STUB
      ;;
  esac

  if [ -n "${stdout}" ]; then
    printf 'echo %q\n' "${stdout}" >> "${path}"
  fi

  echo "exit ${exit_code}" >> "${path}"
  chmod +x "${path}"
}

# Source db-snapshot.sh without auto-invoking main(), and shadow `sleep` so
# die()'s 8-hour stall doesn't hang the test suite.
source_script() {
  # shellcheck disable=SC2317
  sleep() { :; }
  # shellcheck disable=SC1090
  source "${SCRIPT_PATH}"
}

# Return the accumulated args (one line per call) for the named stub.
stub_args() {
  cat "${STUB_LOG}/${1}.args" 2>/dev/null || true
}

# True if the named stub was called at least once.
stub_called() {
  [ -s "${STUB_LOG}/${1}.args" ]
}

# Return the value of <var> from the last captured env of <stub>, or empty.
stub_env_value() {
  local stub="${1}"
  local var="${2}"
  grep "^${var}=" "${STUB_LOG}/${stub}.env" 2>/dev/null | head -1 | cut -d= -f2-
}
