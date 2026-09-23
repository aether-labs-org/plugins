# Containers - AWS options

Read the aws-core skill `aws-containers` before choosing settings.

| Decision | Default | Alternatives |
|---|---|---|
| Orchestrator | ECS | EKS when Kubernetes is an organisational standard |
| Capacity | Fargate | EC2 capacity providers for GPU, daemon sets or steady high utilisation |
| Registry | ECR with image scanning and immutable tags | - |
| Service-to-service | ECS Service Connect | App Mesh is not a default |

Size tasks from load tests, not guesses: CPU and memory per task feed the list-price estimate
directly (`aws_ecs_task_definition` cpu/memory x running tasks).
