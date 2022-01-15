#!/usr/bin/env bash

set -e

die ()
{
  echo "[FATAL]: ${1}"
  exit 1
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

aws_endpoint_url ()
{
  if [ -n "${AWS_ENDPOINT_URL}" ]; then
    echo "--endpoint '${AWS_ENDPOINT_URL}'"
  else
    echo ""
  fi
}

backup-mysql ()
{
  die "MySQL is not yet supported"

  false
}

backup-postgres ()
{
  debug "Backing up postgres database"

  output_file="${SERVICE_NAME}_${TARGET_DATABASE}_$(date '+%Y-%m-%d-%H-%M-%S').sql"
  export PGPASSWORD="${DB_PASSWORD}"

  info "Dumping database to file '${output_file}'"

  # Dump to a file
  pg_dump "${TARGET_DATABASE}" --inserts -U "${DB_USERNAME}" -h "${DB_HOSTNAME}" -p "${DB_PORT}" > "${output_file}"

  info "pg_dump to file '${output_file}' is complete.  Total size is:"
  info "$(du -hs "${output_file}")"

  # Upload file to destination bucket
  info "Uploading to endpoint '${AWS_ENDPOINT_URL}', bucket '${BUCKET_NAME}', key '${PREFIX}/${output_file}'"
  aws s3 cp --endpoint-url="${AWS_ENDPOINT_URL}" "${output_file}" "s3://${BUCKET_NAME}/${PREFIX}/${output_file}"

  retval="$?"
  info "Upload completed with exit code '${retval}'"
  return "${retval}"
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
