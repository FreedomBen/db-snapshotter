# db-snapshotter

Simple script to dump a PostgreSQL or MariaDB database into a .sql.gz file,
and upload it to object storage (S3 compatible, such as Backblaze).

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
  SLACK_API_TOKEN:  '<token>' # optional for slack notifications
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

