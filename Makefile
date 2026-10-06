.PHONY: check validate

check:
	./tests/run.sh

validate:
	claude plugin validate ./plugins/keel-harness --strict
	claude plugin validate ./plugins/solutions-architect --strict
	claude plugin validate ./plugins/second-brain --strict
