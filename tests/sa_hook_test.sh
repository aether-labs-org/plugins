#!/usr/bin/env bash
# Read-only hook (plan Task 3, decisions D13/D14).
set -uo pipefail
fail=0
root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$root/plugins/solutions-architect/hooks/deny_mutations.py"
t() { # t <deny|allow> <tool_name> <tool_input-json> <label>
  local out got
  out="$(printf '{"tool_name":"%s","tool_input":%s}' "$2" "$3" | python3 "$hook")"
  if [ -n "$out" ]; then got=deny; else got=allow; fi
  if [ "$got" = "$1" ]; then echo "  ok   $4"; else echo "  FAIL $4 (got $got)"; fail=1; fi
}
t deny  Bash '{"command":"terraform apply -auto-approve"}' "terraform apply"
t deny  Bash '{"command":"cd infra && terraform destroy"}' "terraform destroy after cd"
t deny  Bash '{"command":"terraform plan -out=tf.plan"}' "terraform plan without -lock=false"
t allow Bash '{"command":"terraform plan -lock=false -out=tf.plan"}' "terraform plan -lock=false"
t allow Bash '{"command":"terraform show -json tf.plan > plan.json"}' "terraform show"
t allow Bash '{"command":"terraform init -backend=false && terraform validate"}' "init + validate"
t deny  Bash '{"command":"terraform state rm aws_s3_bucket.x"}' "terraform state rm"
t allow Bash '{"command":"terraform state list"}' "terraform state list"
t deny  Bash '{"command":"aws ec2 run-instances --image-id ami-1"}' "aws ec2 run-instances"
t deny  Bash '{"command":"aws --region sa-east-1 s3 rm s3://b/k"}' "aws s3 rm with global flag"
t allow Bash '{"command":"aws s3 ls"}' "aws s3 ls"
t allow Bash '{"command":"aws --region us-east-1 pricing get-products --service-code AmazonEC2"}' "aws pricing get-products"
t allow Bash '{"command":"aws accessanalyzer validate-policy --policy-type IDENTITY_POLICY --policy-document file://p.json"}' "access analyzer validate"
t allow Bash '{"command":"aws sts get-caller-identity"}' "sts identity"
t deny  Bash '{"command":"aws bcm-pricing-calculator create-workload-estimate --name x"}' "pricing calculator create (no exceptions)"
t deny  Bash '{"command":"aws logs start-query --log-group-name x"}' "start-* is not read-only"
t deny  Bash '{"command":"cdk deploy --all"}' "cdk deploy"
t deny  Bash '{"command":"kubectl apply -f k.yaml"}' "kubectl apply"
t allow Bash '{"command":"kubectl get pods -A"}' "kubectl get"
t deny  Bash '{"command":"python3 -c \"import boto3; boto3.client(\\\"ec2\\\").terminate_instances(InstanceIds=[\\\"i-1\\\"])\""}' "inline boto3 terminate"
t allow Bash '{"command":"python3 -c \"import boto3; print(boto3.client(\\\"ec2\\\").describe_instances())\""}' "inline boto3 describe"
t allow Bash '{"command":"grep -rn create_bucket docs/"}' "grep mentioning create_bucket"
t allow Bash '{"command":"git commit -m \"add terraform apply docs\""}' "git commit mentioning terraform apply"
t deny  mcp__plugin_aws-core_aws-mcp__aws___run_script '{"script":"call_boto3(\"ec2\", \"run_instances\", {})"}' "run_script run_instances"
t allow mcp__plugin_aws-core_aws-mcp__aws___run_script '{"script":"call_boto3(\"ec2\", \"describe_vpcs\", {})"}' "run_script describe_vpcs"
t allow mcp__plugin_solutions-architect_aws-pricing__get_pricing '{"service_code":"AmazonEC2"}' "pricing MCP"
out="$(printf '{"tool_name":"Bash","tool_input":{"command":"terraform apply"}}' | python3 "$hook")"
printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin)["hookSpecificOutput"]; assert d["permissionDecision"]=="deny" and "D13" in d["permissionDecisionReason"]'
if [ $? -eq 0 ]; then echo "  ok   deny output is a PreToolUse decision citing D13"; else echo "  FAIL deny output shape"; fail=1; fi
exit $fail
