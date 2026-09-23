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

# C1: unrecognised wrappers must not bypass the guard
t deny  Bash '{"command":"bash -c \"terraform apply -auto-approve\""}' "bash -c terraform apply"
t deny  Bash '{"command":"sh -c \"aws ec2 terminate-instances --instance-ids i-1\""}' "sh -c aws terminate-instances"
t deny  Bash '{"command":"zsh -c \"terraform destroy\""}' "zsh -c terraform destroy"
t deny  Bash '{"command":"dash -c \"terraform apply -auto-approve\""}' "dash -c terraform apply"
t deny  Bash '{"command":"ksh -c \"aws ec2 terminate-instances --instance-ids i-1\""}' "ksh -c aws terminate-instances"
t deny  Bash '{"command":"eval \"terraform apply -auto-approve\""}' "eval terraform apply"
t deny  Bash '{"command":"timeout 30 terraform apply -auto-approve"}' "timeout wrapper"
t deny  Bash '{"command":"xargs terraform apply"}' "xargs wrapper"
t deny  Bash '{"command":"find . -exec aws s3 rm {} \\;"}' "find -exec wrapper"
t deny  Bash '{"command":"nice -n 5 terraform destroy"}' "nice -n wrapper"
t deny  Bash '{"command":"env -i terraform apply"}' "env -i wrapper"
t deny  Bash '{"command":"sudo -u x aws ec2 run-instances"}' "sudo -u wrapper"
t deny  Bash '{"command":"echo terraform apply"}' "echo terraform apply (false positive is acceptable per C1)"

# C1 follow-up: combined short-option clusters containing "c" also mean -c
t deny  Bash '{"command":"bash -lc \"aws s3 rm s3://b/k\""}' "bash -lc combined short flags"
t deny  Bash '{"command":"bash -ec \"terraform apply -auto-approve\""}' "bash -ec combined short flags"
t deny  Bash '{"command":"bash -xc \"terraform destroy\""}' "bash -xc combined short flags"
t deny  Bash '{"command":"bash --login -c \"terraform apply -auto-approve\""}' "bash --login -c"
t deny  Bash '{"command":"bash -o pipefail -c \"terraform apply -auto-approve\""}' "bash -o pipefail -c"
t deny  Bash '{"command":"zsh -fc \"terraform destroy\""}' "zsh -fc combined short flags"
t deny  Bash '{"command":"sh -c -- \"aws ec2 terminate-instances --instance-ids i-1\""}' "sh -c -- (end of options before command)"

out="$(printf '{"tool_name":"Bash","tool_input":{"command":"terraform apply"}}' | python3 "$hook")"
printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin)["hookSpecificOutput"]; assert d["permissionDecision"]=="deny" and "D13" in d["permissionDecisionReason"]'
if [ $? -eq 0 ]; then echo "  ok   deny output is a PreToolUse decision citing D13"; else echo "  FAIL deny output shape"; fail=1; fi

# C2: fail-closed on unexpected input
out="$(printf 'not json at all' | python3 "$hook")"; rc=$?
printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin)["hookSpecificOutput"]; assert d["permissionDecision"]=="deny" and "D13" in d["permissionDecisionReason"]'
if [ $? -eq 0 ] && [ "$rc" -eq 0 ]; then echo "  ok   non-JSON stdin fails closed (deny, exit 0)"; else echo "  FAIL non-JSON stdin does not fail closed"; fail=1; fi

out="$(printf '{"tool_name":"Bash","tool_input":"not-a-dict"}' | python3 "$hook")"; rc=$?
printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin)["hookSpecificOutput"]; assert d["permissionDecision"]=="deny"'
if [ $? -eq 0 ] && [ "$rc" -eq 0 ]; then echo "  ok   non-dict tool_input fails closed (deny, exit 0)"; else echo "  FAIL non-dict tool_input does not fail closed"; fail=1; fi

out="$(printf '[1,2,3]' | python3 "$hook")"; rc=$?
printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin)["hookSpecificOutput"]; assert d["permissionDecision"]=="deny"'
if [ $? -eq 0 ] && [ "$rc" -eq 0 ]; then echo "  ok   non-dict top-level JSON fails closed (deny, exit 0)"; else echo "  FAIL non-dict top-level JSON does not fail closed"; fail=1; fi

exit $fail
