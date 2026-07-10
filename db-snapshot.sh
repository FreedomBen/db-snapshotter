#!/usr/bin/env bash


# Variables for configuration:
# DB_TYPE:  'postgres'  # || 'mysql'
# AWS_ENDPOINT_URL:   'https://s3.us-west-002.backblazeb2.com'
# TARGET_DATABASE:  'service_name_prod'
# BUCKET_NAME:  'db-backups'
# DB_PORT:  '25060'
# PREFIX:  'daily'
# SERVICE_NAME:  'service_name'
# DB_USERNAME: '<redacted>'
# DB_PASSWORD: '<redacted>'
# DB_HOSTNAME: '<redacted>'
# AWS_ACCESS_KEY_ID: '<redacted>'
# AWS_SECRET_ACCESS_KEY: '<redacted>'
#
# Backup encryption (enabled by default):
# ENCRYPTION_ENABLED='true'  # set to 'false'/'0'/'no'/'off'/'disabled' to disable
# ENCRYPTION_KEY='<key>'     # required when encryption is enabled.  See README for
                             # instructions on generating a strong key.
#
# Compression:
# ZSTD_LEVEL='19'            # zstd level, integer 1 (fastest) to 19 (smallest,
                             # the default).  Level 19 on a multi-GB dump can take
                             # hours; ~10 is several times faster for a modestly
                             # larger file.


# To use Slack integration, set:
# SLACK_API_TOKEN='xoxp-...'
# SLACK_CHANNEL_DEBUG='#debug'  # If set, debug mode will be enabled
# SLACK_CHANNEL_INFO='#info'
# SLACK_CHANNEL_WARNING='#warning'
# SLACK_CHANNEL_ERROR='#main'
# SLACK_CHANNEL_SUCCESS='#main'
# SLACK_USERNAME='Some Username'
# SLACK_ICON_EMOJI=':database:'


# Path overrides (rarely set in production; mainly for tests and unusual deployments)
# SNAPSHOT_DIR:  directory the dump is written to before upload (default: /snapshot)
# PODINFO_DIR:   downward-API mount whose `podname` and `namespace` files are
#                interpolated into Slack error messages (default: /etc/podinfo)
SNAPSHOT_DIR="${SNAPSHOT_DIR:-/snapshot}"
PODINFO_DIR="${PODINFO_DIR:-/etc/podinfo}"
ZSTD_LEVEL="${ZSTD_LEVEL:-19}"

START_TIME_SEC="$(date '+%s')"

runtime_seconds ()
{
  echo $(( $(date '+%s') - START_TIME_SEC ))
}

die ()
{
  echo "[FATAL]:  ${1}"
  slack_error "[FATAL]: $(date): Backup of database '${TARGET_DATABASE}' failed after $(runtime_seconds) seconds: ${1}"
  exit 1
}

log ()
{
  echo "[LOG] - $(date): ${1}"
}

warn ()
{
  echo "[WARN]: ${1}"
}

info ()
{
  echo "[INFO]: ${1}"
}

debug ()
{
  echo "[DEBUG]: ${1}"
}

slack_icon_emoji ()
{
  if [ -n "${SLACK_ICON_EMOJI}" ]; then
    echo "${SLACK_ICON_EMOJI}"
  else
    echo ":database:"
  fi
}

slack_username ()
{
  if [ -n "${SLACK_USERNAME}" ]; then
    echo "${SLACK_USERNAME}"
  else
    echo "DB Snapshotter for ${SERVICE_NAME}"
  fi
}

send_slack_message ()
{
  if [ -n "${SLACK_API_TOKEN}" ]; then
    debug "SLACK_API_TOKEN is set.  sending slack message to channel ${1}"
    curl \
      --silent \
      --show-error \
      --data-urlencode "token=${SLACK_API_TOKEN}" \
      --data-urlencode "channel=${1}" \
      --data-urlencode "text=${2}" \
      --data-urlencode "username=$(slack_username)" \
      --data-urlencode "icon_emoji=$(slack_icon_emoji)" \
      'https://slack.com/api/chat.postMessage'
    echo # add a new-line to the output so it's easier to read the logs
  else
    debug "SLACK_API_TOKEN is not present.  Message not sent to slack channel '${1}' message: '${2}'"
  fi
}

slack_success ()
{
  send_slack_message "${SLACK_CHANNEL_SUCCESS}" ":white_check_mark:  ${1}"
}

slack_error ()
{
  send_slack_message "${SLACK_CHANNEL_ERROR}" ":x:  ${1}"
}

slack_warning ()
{
  send_slack_message "${SLACK_CHANNEL_WARNING}" ":warning:  ${1}"
}

slack_debug ()
{
  send_slack_message "${SLACK_CHANNEL_DEBUG}" ":information_source:  ${1}"
}

slack_info ()
{
  send_slack_message "${SLACK_CHANNEL_INFO}" ":information_source:  ${1}"
}

file_size ()
{
  du -hs "${1}" | awk '{ print $1 }'
}

encryption_enabled ()
{
  # Default to enabled when ENCRYPTION_ENABLED is unset
  case "${ENCRYPTION_ENABLED:-true}" in
    false|False|FALSE|0|no|No|NO|off|Off|OFF|disabled|Disabled|DISABLED)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

encrypt_file ()
{
  local input_file="${1}"
  local output_file="${2}"

  info "Encrypting '${input_file}' with AES-256-CBC -> '${output_file}'"
  # -pass env:ENCRYPTION_KEY keeps the key off the process command line.
  # -pbkdf2 + -iter derives the AES key from ENCRYPTION_KEY via PBKDF2.
  openssl enc -aes-256-cbc -salt -pbkdf2 -iter 100000 \
    -in "${input_file}" \
    -out "${output_file}" \
    -pass env:ENCRYPTION_KEY 2> opensslstderr.log
  local retval="$?"

  if [ "${retval}" != '0' ]; then
    local opensslstderr
    opensslstderr="$(cat opensslstderr.log)"
    die "openssl encryption exited with status '${retval}': \`\`\`${opensslstderr}\`\`\`"
  fi

  # Remove the unencrypted source so only the encrypted artifact remains on disk
  rm -f "${input_file}"
}

backup-mysql ()
{
  debug "Backing up mysql database"

  local sql_file
  sql_file="${SERVICE_NAME}_${TARGET_DATABASE}_$(date '+%Y-%m-%d-%H-%M-%S')-mysql.sql"
  local output_file="${sql_file}.zst"
  # Pass the password via MYSQL_PWD so it does not appear in the process list.
  export MYSQL_PWD="${DB_PASSWORD}"

  info "Dumping database to file '${sql_file}'"
  slack_info "Beginning dump of database '${TARGET_DATABASE}' at $(date)"

  # Dump to a file
  info "Dumping database at: '${DB_HOSTNAME}'"
  mysqldump "${TARGET_DATABASE}" -h "${DB_HOSTNAME}" -P "${DB_PORT}" -u "${DB_USERNAME}" > "${sql_file}" 2> mysqlstderr.log
  local retval="$?"

  debug "mysqldump retval is '${retval}'"

  local mysqlstderr
  mysqlstderr="$(cat mysqlstderr.log)"
  info "mysqldump output: ${mysqlstderr}"

  if [ "${retval}" != '0' ]; then
    die "Check logs with: \`\`\`kubectl logs $(cat "${PODINFO_DIR}/podname") -n $(cat "${PODINFO_DIR}/namespace")\`\`\` mysqldump exited with status '${retval}': \`\`\`${mysqlstderr}\`\`\`"
  fi

  local size
  size="$(file_size "${sql_file}")"
  info "mysqldump to file '${sql_file}' is complete.  Total uncompressed size is: ${size}"

  zstd -T0 "-${ZSTD_LEVEL}" --rm "${sql_file}"
  size="$(file_size "${output_file}")"
  info "Compression of mysqldump file '${output_file}' is complete.  Total compressed size is: ${size}"

  if encryption_enabled; then
    local encrypted_file="${output_file}.enc"
    encrypt_file "${output_file}" "${encrypted_file}"
    output_file="${encrypted_file}"
    size="$(file_size "${output_file}")"
    info "Encryption of file '${output_file}' is complete.  Total encrypted size is: ${size}"
  fi

  # Upload file to destination bucket
  upload_file_to_bucket "${output_file}" "${size}"
  return "$?"
}

backup-postgres ()
{
  debug "Backing up postgres database"

  local sql_file
  sql_file="${SERVICE_NAME}_${TARGET_DATABASE}_$(date '+%Y-%m-%d-%H-%M-%S')-pgsql.sql"
  local output_file="${sql_file}.zst"
  export PGPASSWORD="${DB_PASSWORD}"

  info "Dumping database to file '${sql_file}'"
  slack_info "Beginning dump of database '${TARGET_DATABASE}' at $(date)"

  # Dump to a file
  pg_dump "${TARGET_DATABASE}" --inserts -U "${DB_USERNAME}" -h "${DB_HOSTNAME}" -p "${DB_PORT}" > "${sql_file}" 2> pgstderr.log
  local retval="$?"

  debug "pg_dump retval is '${retval}'"

  local pgstderr
  pgstderr="$(cat pgstderr.log)"
  info "pg_dump output: ${pgstderr}"

  if [ "${retval}" != '0' ]; then
    die "Check logs with: \`\`\`kubectl logs $(cat "${PODINFO_DIR}/podname") -n $(cat "${PODINFO_DIR}/namespace")\`\`\` pg_dump exited with status '${retval}': \`\`\`${pgstderr}\`\`\`"
  fi

  local size
  size="$(file_size "${sql_file}")"
  info "pg_dump to file '${sql_file}' is complete.  Total uncompressed size is: ${size}"

  zstd -T0 "-${ZSTD_LEVEL}" --rm "${sql_file}"
  size="$(file_size "${output_file}")"
  info "Compression of pg_dump file '${output_file}' is complete.  Total compressed size is: ${size}"

  if encryption_enabled; then
    local encrypted_file="${output_file}.enc"
    encrypt_file "${output_file}" "${encrypted_file}"
    output_file="${encrypted_file}"
    size="$(file_size "${output_file}")"
    info "Encryption of file '${output_file}' is complete.  Total encrypted size is: ${size}"
  fi

  # Upload file to destination bucket
  upload_file_to_bucket "${output_file}" "${size}"
  return "$?"
}

upload_file_to_bucket ()
{
  local output_file="${1}"
  local size="${2}"

  # Upload file to destination bucket
  info "Uploading to endpoint '${AWS_ENDPOINT_URL:-<default>}', bucket '${BUCKET_NAME}', key '${PREFIX}/${output_file}'"
  if [ -n "${AWS_ENDPOINT_URL}" ]; then
    aws s3 cp --endpoint-url="${AWS_ENDPOINT_URL}" "${output_file}" "s3://${BUCKET_NAME}/${PREFIX}/${output_file}"
  else
    aws s3 cp "${output_file}" "s3://${BUCKET_NAME}/${PREFIX}/${output_file}"
  fi

  local retval="$?"
  info "Upload completed with exit code '${retval}'"
  if [ "${retval}" = '0' ]; then
    slack_success "Backup of database '${TARGET_DATABASE}' succeeded at $(date) after running for $(runtime_seconds) seconds.  Total size: ${size}."
  else
    slack_error "Backup of database '${TARGET_DATABASE}' dumped successful but uploading to object storage failed at $(date) after running for $(runtime_seconds) seconds.  Check logs with: \`\`\`kubectl logs $(cat "${PODINFO_DIR}/podname") -n $(cat "${PODINFO_DIR}/namespace")\`\`\`"
  fi
  echo # flush slack output \n
  return "${retval}"
}

verify_zstd_level ()
{
  case "${ZSTD_LEVEL}" in
    ''|*[!0-9]*)
      die "ZSTD_LEVEL '${ZSTD_LEVEL}' is not a positive integer.  Must be 1 (fastest) to 19 (smallest)."
      ;;
  esac

  if [ "${ZSTD_LEVEL}" -lt 1 ] || [ "${ZSTD_LEVEL}" -gt 19 ]; then
    die "ZSTD_LEVEL '${ZSTD_LEVEL}' is out of range.  Must be 1 (fastest) to 19 (smallest)."
  fi

  info "zstd compression level is ${ZSTD_LEVEL}"
}

verify_credentials ()
{
  if [ -z "${AWS_SECRET_ACCESS_KEY}" ]; then
    die "AWS_SECRET_ACCESS_KEY is not set.  Must be set"
  elif [ -z "${AWS_ACCESS_KEY_ID}" ]; then
    die "AWS_ACCESS_KEY_ID is not set.  Must be set"
  elif [ -z "${AWS_ENDPOINT_URL}" ]; then
    warn "AWS_ENDPOINT_URL is not set.  Assuming default"
  fi

  if encryption_enabled; then
    if [ -z "${ENCRYPTION_KEY}" ]; then
      die "Encryption is enabled but ENCRYPTION_KEY is not set.  Set ENCRYPTION_KEY, or set ENCRYPTION_ENABLED=false to disable encryption."
    fi
    info "Backup encryption is enabled (AES-256-CBC)."
  else
    warn "Backup encryption is disabled (ENCRYPTION_ENABLED='${ENCRYPTION_ENABLED}').  Backups will be uploaded unencrypted."
  fi
}

main ()
{
  debug "Verifying that we have credentials"
  verify_credentials

  debug "Verifying the zstd compression level"
  verify_zstd_level

  debug "Making output directory ${SNAPSHOT_DIR}"
  mkdir -p "${SNAPSHOT_DIR}"

  debug "Changing directory to ${SNAPSHOT_DIR}"
  cd "${SNAPSHOT_DIR}" || die "Could not cd to ${SNAPSHOT_DIR}"

  # The first letter is what matters.  supports "mysql" or "postgres"
  debug "Checking database type"
  if [[ "$DB_TYPE" =~ ^[m] ]]; then
    info "Database type is MySQL"
    backup-mysql
  elif [[ "$DB_TYPE" =~ ^[p] ]]; then
    info "Database type is PostgreSQL"
    backup-postgres
  else
    die "Unknown DB_TYPE '${DB_TYPE}'.  Must start with 'm' (mysql) or 'p' (postgres)."
  fi
}

# Only run main when this script is executed directly, not when sourced (e.g. by tests).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
