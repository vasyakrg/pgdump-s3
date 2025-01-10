# pgdump-s3

[![dockeri.co](http://dockeri.co/image/bartversluijs/pgdump-s3)](https://hub.docker.com/r/bartversluijs/pgdump-s3/)

> Docker Image with Alpine Linux, pg_dump and awscli for backup postgres database to s3

# Use

## Periodic backup

Run every day at 2 am

```bash
docker run -d --name pgdump \
  -e "POSTGRESQL_URI=postgres://user:pass@host:port/dbname"
  -e "AWS_ACCESS_KEY_ID=your_aws_access_key"
  -e "AWS_SECRET_ACCESS_KEY=your_aws_secret_access_key"
  -e "AWS_DEFAULT_REGION=us-east-1"
  -e "S3_BUCKET=your_aws_bucket"
  -e "S3_PATH=/pg_dump"
  -e "BACKUP_CRON_SCHEDULE=0 2 * * *"
  bartversluijs/pgdump-s3
```

## Immediate backup

```bash
docker run -d --name pgdump \
  -e "POSTGRESQL_URI=postgres://user:pass@host:port/dbname"
  -e "AWS_ACCESS_KEY_ID=your_aws_access_key"
  -e "AWS_SECRET_ACCESS_KEY=your_aws_secret_access_key"
  -e "AWS_DEFAULT_REGION=us-east-1"
  -e "S3_BUCKET=your_aws_bucket"
  -e "S3_PATH=/pg_dump"
  bartversluijs/pgdump-s3
```

# Options

| Environment variable | Description |
| --- | --- |
| `POSTGRESQL_URI` | URI of the PostgreSQL instance |
| `AWS_ACCESS_KEY_ID` | Access key ID of your S3 storage |
| `AWS_SECRET_ACCESS_KEY` | Secret access key of your S3 storage |
| `AWS_DEFAULT_REGION` | Region of your S3 storage |
| `S3_BUCKET` | Bucket name |
| `S3_PATH` | Path of where to store the dump |
| `S3_ENDPOINT` | Endpoint of your S3 storage |  
| `BACKUP_CRON_SCHEDULE` | Cron schedule |

  # IAM Policity

You need to add a user with the following policies. Be sure to change `your_bucket` by the correct.

```xml
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "Stmt1412062044000",
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:PutObjectAcl"
            ],
            "Resource": [
                "arn:aws:s3:::your_bucket/*"
            ]
        },
        {
            "Sid": "Stmt1412062128000",
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::your_bucket"
            ]
        }
    ]
}
```

## Credits

[drivetech/pgdump-s3](https://github.com/Drivetech/pgdump-s3)

## License

[MIT](https://tldrlegal.com/license/mit-license)
