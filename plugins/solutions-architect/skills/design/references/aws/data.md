# Data and analytics - AWS options

The official `aws-data-analytics` plugin covers these services in depth; recommend it when the
solution has a data platform component.

| Need | Default | Alternatives |
|---|---|---|
| Data lake storage | S3 + S3 Tables (Apache Iceberg) | plain Parquet on S3 for small lakes |
| Ingestion / ETL | Glue | EMR for large Spark estates; Kinesis Firehose for streams |
| Ad-hoc SQL | Athena | Redshift Serverless for frequent BI workloads |
| Governance | Lake Formation | - |

Record data classification per data set (from requirements) and where personal data is masked
or tokenised before it reaches analytics.
