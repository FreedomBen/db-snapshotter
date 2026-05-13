# db-snapshotter

Simple script to dump a PostgreSQL or MariaDB database into a zstd-compressed
`.sql.zst` file, optionally encrypt it with AES-256, and upload it to object
storage (S3 compatible, such as Backblaze).  Backup encryption is enabled by
default.

## Quick Start

You can find sample Kubernetes manifest in `k8s/examples`.  The configuration
is passed in to the script via environment variables.  Non sensitive values
should be passed through a `ConfigMap`, while sensitive values should use
`Secret`s.

### 1.  Gather configuration information

You will need to provide values for the following variables:

- `DB_TYPE:  'postgres'  # || 'mysql'`
- `AWS_ENDPOINT_URL:   'https://s3.us-west-002.backblazeb2.com'`
- `TARGET_DATABASE:  'service_name_prod'`
- `BUCKET_NAME:  'db-backups'`
- `DB_PORT:  '25060'`
- `PREFIX:  'daily'`
- `SERVICE_NAME:  'service_name'`
- `DB_USERNAME: '<redacted>'`
- `DB_PASSWORD: '<redacted>'`
- `DB_HOSTNAME: '<redacted>'`
- `AWS_ACCESS_KEY_ID: '<redacted>'`
- `AWS_SECRET_ACCESS_KEY: '<redacted>'`

For backup encryption (enabled by default):

- `ENCRYPTION_ENABLED: 'true'`  — set to `'false'` (or `0`/`no`/`off`/`disabled`) to upload unencrypted backups.  Defaults to `'true'` when unset.
- `ENCRYPTION_KEY: '<key>'`     — required when `ENCRYPTION_ENABLED` is `'true'`.  See [Generating an encryption key](#generating-an-encryption-key) below.

Optionally, to enable notifications over Slack, set:

- `SLACK_API_TOKEN:  '<token>'`
- `SLACK_CHANNEL_INFO: '<redacted>'`
- `SLACK_CHANNEL_ERROR: '<redacted>'`
- `SLACK_CHANNEL_SUCCESS: '<redacted>'`
- `SLACK_USERNAME: '<redacted>'  # optional customization`
- `SLACK_ICON_EMOJI: '<redacted>'  # optional customization`


### 2.  Create Secret

Configure and create a `Secret` defining the variables.  Here is an example:

```yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: db-snapshotter-service-name-secrets
  namespace: db-snapshotter-prod
  labels:
    app: db-snapshotter
type: Opaque
stringData:
  DB_USERNAME: '<redacted>'
  DB_PASSWORD: '<redacted>'
  DB_HOSTNAME: '<redacted>'
  AWS_ACCESS_KEY_ID: '<redacted>'
  AWS_SECRET_ACCESS_KEY: '<redacted>'
  ENCRYPTION_KEY: '<redacted>'  # required when ENCRYPTION_ENABLED is 'true'
  SLACK_API_TOKEN:  '<token>'   # optional for slack notifications
```

### 3.  Update Configuration in `ConfigMap`

You can use one of the examples in `k8s/examples`

```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: db-snapshotter-service-name-config
  namespace: db-snapshotter-prod
  labels:
    app: db-snapshotter
data:
  DB_TYPE: 'postgres'  # || 'mysql'
  AWS_ENDPOINT_URL:  'https://s3.us-west-002.backblazeb2.com'
  TARGET_DATABASE: 'service_name_prod'
  BUCKET_NAME: 'db-backups'
  DB_PORT: '25060'
  PREFIX: 'daily'
  SERVICE_NAME: 'service_name'
  ENCRYPTION_ENABLED: 'true'                          # set to 'false' to skip AES-256 encryption
  SLACK_CHANNEL_INFO: '#infra-info'                   # channel to send info messages to
  SLACK_CHANNEL_ERROR: '#infra-error'                 # channel to send error messages to
  SLACK_CHANNEL_SUCCESS: '#infra-info'                # channel to send success messages to
  SLACK_USERNAME: 'DB Snapshot for service-name prod' # optional username to post as
  SLACK_ICON_EMOJI: ':database:'                      # optional emoji to use for avatar
```

### 4.  Create a `Job` or `CronJob`

If you only want to run the script once or on demand, create a `Job` object.
If you want to run the script periodically, create a `CronJob` object.

Here is an example `CronJob` that will run at 10 PM every day:

```yaml
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: db-snapshotter
  namespace: db-snapshotter-prod
  labels:
    app: db-snapshotter
spec:
  schedule: "0 22 * * *" # 10 PM every day
  jobTemplate:
    metadata:
      name: db-snapshotter-prod-job
      namespace: db-snapshotter-prod
      labels:
        app: db-snapshotter
    spec:
      backoffLimit: 1
      activeDeadlineSeconds: 1800
      template:
        metadata:
          namespace: db-snapshotter-prod
          labels:
            app: db-snapshotter
        spec:
          containers:
          - name: db-snapshotter
            image: docker.io/freedomben/db-snapshotter:latest
            imagePullPolicy: Always
            envFrom:
              - configMapRef:
                  name: db-snapshotter-service-name-config
              - secretRef:
                  name: db-snapshotter-service-name-secrets
          restartPolicy: Never
```

### 5.  Run the Job

If you created a `Job` it will run immediately.  If you created a `CronJob`
but would like to run it immediately for testing purposes (a wise plan), you
can create a `Job` from the `CronJob` with:

```bash
CRONJOB_NAME='db-snapshotter'
NEW_JOB_NAME="db-snapshotter-manual-run-$(date '+%Y-%m-%d-%H-%M-%S')"

kubectl create job --from="cronjob/${CRONJOB_NAME}" "${NEW_JOB_NAME}"
```

## Backup encryption

`db-snapshotter` encrypts the zstd-compressed dump with AES-256-CBC before
uploading it to object storage.  The cipher key is derived from `ENCRYPTION_KEY` using
PBKDF2 (SHA-256, 100,000 iterations) with a random per-file salt, via
`openssl enc -aes-256-cbc -salt -pbkdf2 -iter 100000`.

Encryption is controlled by two environment variables:

| Variable             | Default | Purpose                                                                                                               |
| -------------------- | ------- | --------------------------------------------------------------------------------------------------------------------- |
| `ENCRYPTION_ENABLED` | `true`  | Enables/disables encryption.  Falsy values (`false`, `0`, `no`, `off`, `disabled`) disable it; everything else enables it. |
| `ENCRYPTION_KEY`     | _none_  | The secret used to derive the AES-256 key.  **Required** when encryption is enabled; the job exits early if missing.   |

When encryption is enabled the uploaded object is named
`<service>_<database>_<timestamp>-{pgsql,mysql}.sql.zst.enc`.  When disabled
it is the usual `.sql.zst`.

### Generating an encryption key

Generate a high-entropy key on a trusted machine.  Any of these works:

```bash
# 48 random bytes, base64-encoded (recommended — ~64 chars, no padding issues)
openssl rand -base64 48

# 32 random bytes, hex-encoded (64 chars)
openssl rand -hex 32

# Or use any password manager / KMS-generated secret that is at least 32 chars
```

Store the key in a password manager or KMS **separately from the backup
storage**.  If the key is lost, the encrypted backups cannot be recovered.
If the key is leaked, rotate it and re-encrypt or replace existing backups.

### Setting the key for the backup process

The key is read from the `ENCRYPTION_KEY` environment variable and is never
written to the command line, so it does not show up in `ps`.  Put it in the
`Secret` that the Job loads via `envFrom`:

```bash
# One-off: create/replace the Secret containing all backup credentials
kubectl create secret generic db-snapshotter-service-name-secrets \
  --namespace db-snapshotter-prod \
  --from-literal=DB_USERNAME='<redacted>' \
  --from-literal=DB_PASSWORD='<redacted>' \
  --from-literal=DB_HOSTNAME='<redacted>' \
  --from-literal=AWS_ACCESS_KEY_ID='<redacted>' \
  --from-literal=AWS_SECRET_ACCESS_KEY='<redacted>' \
  --from-literal=ENCRYPTION_KEY="$(openssl rand -base64 48)"
```

Or add it to the `stringData` block of `k8s/example/secrets.yaml` and apply
the manifest.  See [`k8s/example/secrets.yaml`](k8s/example/secrets.yaml)
for the canonical layout.

To run locally for testing:

```bash
export ENCRYPTION_KEY="$(openssl rand -base64 48)"
export ENCRYPTION_ENABLED='true'
./db-snapshot.sh
```

### Disabling encryption

Set `ENCRYPTION_ENABLED='false'` in the `ConfigMap` (or unset
`ENCRYPTION_KEY` and set the flag).  When disabled the job logs a warning
and uploads the plain `.sql.zst` file.

### Decrypting a backup

To restore an encrypted backup, download it from object storage and decrypt
it with the same key:

```bash
export ENCRYPTION_KEY='<the key used to create the backup>'

openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 \
  -in service_name_service_name_prod_2026-05-13-22-00-00-pgsql.sql.zst.enc \
  -out service_name_service_name_prod_2026-05-13-22-00-00-pgsql.sql.zst \
  -pass env:ENCRYPTION_KEY

unzstd service_name_service_name_prod_2026-05-13-22-00-00-pgsql.sql.zst
# Then restore via psql / mysql as usual.
```

