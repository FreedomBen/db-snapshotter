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


# To use Slack integration, set:
# SLACK_API_TOKEN='xoxp-...'
# SLACK_CHANNEL_DEBUG='#debug'  # If set, debug mode will be enabled
# SLACK_CHANNEL_INFO='#info'
# SLACK_CHANNEL_WARNING='#warning'
# SLACK_CHANNEL_ERROR='#main'
# SLACK_CHANNEL_SUCCESS='#main'
# SLACK_USERNAME='Some Username'
# SLACK_ICON_EMOJI=':database:'


START_TIME_SEC="$(date '+%s')"

runtime_seconds ()
{
  echo $(( $(date '+%s') - $START_TIME_SEC ))
}

die ()
{
  echo "[FATAL]:  ${1}"
  slack_error "[FATAL]: $(date): Backup of database '${TARGET_DATABASE}' failed after $(runtime_seconds) seconds: ${1}"
  sleep 28800
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
      --data "token=${SLACK_API_TOKEN}&channel=#${1}&text=${2}&username=$(slack_username)&icon_emoji=$(slack_icon_emoji)" \
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

aws_endpoint_url ()
{
  if [ -n "${AWS_ENDPOINT_URL}" ]; then
    echo "--endpoint '${AWS_ENDPOINT_URL}'"
  else
    echo ""
  fi
}

file_size ()
{
  echo "$(du -hs "${1}" | awk '{ print $1 }')"
}

backup-mysql ()
{
  debug "Backing up mysql database"

  local sql_file="${SERVICE_NAME}_${TARGET_DATABASE}_$(date '+%Y-%m-%d-%H-%M-%S')-mysql.sql"
  local output_file="${sql_file}.gz"

  info "Dumping database to file '${sql_file}'"
  slack_info "Beginning dump of database '${TARGET_DATABASE}' at $(date)"

  # Dump to a file
  info "Dumping database at: '${DB_HOSTNAME}'"
  mysqldump "${TARGET_DATABASE}" -h "${DB_HOSTNAME}" -P "${DB_PORT}" -u "${DB_USERNAME}" -p"${DB_PASSWORD}" > "${sql_file}" 2> mysqlstderr.log
  local retval="$?"

  debug "mysqldump retval is '${retval}'"

  local mysqlstderr="$(cat mysqlstderr.log)"
  info "mysqldump output: ${mysqlstderr}"

  if [ "${retval}" != '0' ]; then
    die "Check logs with: \`\`\`kubectl logs $(cat /etc/podinfo/podname) -n $(cat /etc/podinfo/namespace)\`\`\` mysqldump exited with status '${retval}': \`\`\`${mysqlstderr}\`\`\`"
  fi

  local size="$(file_size "${sql_file}")"
  info "mysqldump to file '${sql_file}' is complete.  Total uncompressed size is: ${size}"

  gzip "${sql_file}"
  size="$(file_size "${output_file}")"
  info "Compression of mysqldump file '${output_file}' is complete.  Total compressed size is: ${size}"

  # Upload file to destination bucket
  retval="$(upload_file_to_bucket "${output_file}" "${size}")"
  return ${retval}
}

backup-postgres ()
{
  debug "Backing up postgres database"

  local sql_file="${SERVICE_NAME}_${TARGET_DATABASE}_$(date '+%Y-%m-%d-%H-%M-%S')-pgsql.sql"
  local output_file="${sql_file}.gz"
  export PGPASSWORD="${DB_PASSWORD}"

  info "Dumping database to file '${sql_file}'"
  slack_info "Beginning dump of database '${TARGET_DATABASE}' at $(date)"

  # Dump to a file
  pg_dump "${TARGET_DATABASE}" --inserts -U "${DB_USERNAME}" -h "${DB_HOSTNAME}" -p "${DB_PORT}" > "${sql_file}" 2> pgstderr.log
  local retval="$?"

  debug "pg_dump retval is '${retval}'"

  local pgstderr="$(cat pgstderr.log)"
  info "pg_dump output: ${pgstderr}"

  if [ "${retval}" != '0' ]; then
    die "Check logs with: \`\`\`kubectl logs $(cat /etc/podinfo/podname) -n $(cat /etc/podinfo/namespace)\`\`\` pg_dump exited with status '${retval}': \`\`\`${pgstderr}\`\`\`"
  fi

  local size="$(file_size "${sql_file}")"
  info "pg_dump to file '${sql_file}' is complete.  Total uncompressed size is: ${size}"

  gzip "${sql_file}"
  size="$(file_size "${output_file}")"
  info "Compression of pg_dump file '${output_file}' is complete.  Total compressed size is: ${size}"

  # Upload file to destination bucket
  retval="$(upload_file_to_bucket "${output_file}" "${size}")"
  return ${retval}
}

upload_file_to_bucket ()
{
  local output_file="${1}"
  local size="${2}"

  # Upload file to destination bucket
  info "Uploading to endpoint '${AWS_ENDPOINT_URL}', bucket '${BUCKET_NAME}', key '${PREFIX}/${output_file}'"
  aws s3 cp --endpoint-url="${AWS_ENDPOINT_URL}" "${output_file}" "s3://${BUCKET_NAME}/${PREFIX}/${output_file}"

  local retval="$?"
  info "Upload completed with exit code '${retval}'"
  if [ "${retval}" = '0' ]; then
    slack_success "Backup of database '${TARGET_DATABASE}' succeeded at $(date) after running for $(runtime_seconds) seconds.  Total size: ${size}."
  else
    slack_error "Backup of database '${TARGET_DATABASE}' dumped successful but uploading to object storage failed at $(date) after running for $(runtime_seconds) seconds.  Check logs with: \`\`\`kubectl logs $(cat /etc/podinfo/podname) -n $(cat /etc/podinfo/namespace)\`\`\`"
  fi
  echo # flush slack output \n
  return ${retval}
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
}

main ()
{
  debug "Verifying that we have credentials"
  verify_credentials

  debug "Making output directory /snapshot"
  mkdir -p /snapshot

  debug "Changing directory to /snapshot"
  cd /snapshot

  # The first letter is what matters.  supports "mysql" or "postgres"
  debug "Checking database type"
  if [[ "$DB_TYPE" =~ ^[m] ]]; then
    info "Database type is MySQL"
    backup-mysql
  elif [[ "$DB_TYPE" =~ ^[p] ]]; then
    info "Database type is PostgreSQL"
    backup-postgres
  fi
}

main "$@"
