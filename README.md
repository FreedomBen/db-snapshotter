# db-snapshotter

Simple script to dump a PostgreSQL or MariaDB database into a .sql file,
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
- `TARGET_DATABASE:  `'service_name_prod'``
- `BUCKET_NAME:  'db-backups'`
- `DB_PORT:  '25060'`
- `PREFIX:  'daily'`
- `SERVICE_NAME:  'service_name'`
- `DB_USERNAME: '<redacted>'`
- `DB_PASSWORD: '<redacted>'`
- `DB_HOSTNAME: '<redacted>'`
- `AWS_ACCESS_KEY_ID: '<redacted>'`
- `AWS_SECRET_ACCESS_KEY: '<redacted>'`

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

