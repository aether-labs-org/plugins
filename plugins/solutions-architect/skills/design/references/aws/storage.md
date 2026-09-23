# Storage - AWS options

Read the aws-core skill `aws-storage` before choosing settings.

| Need | Default | Alternatives |
|---|---|---|
| Objects, static assets, data lake | S3 Standard with lifecycle rules | S3 Intelligent-Tiering for unknown access patterns; Glacier classes for archives |
| Shared POSIX file system | EFS | FSx for Windows / Lustre / NetApp ONTAP for their protocols |
| Block storage for EC2 | EBS gp3 | io2 only when an NFR needs guaranteed IOPS |

Defaults: block public access on every bucket; SSE-KMS for personal data (LGPD); versioning on
buckets holding data that cannot be recreated; lifecycle to cheaper classes after the access
pattern is known.
