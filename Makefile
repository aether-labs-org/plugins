.PHONY: check validate

check:
	./tests/run.sh

validate:
	claude plugin validate ./plugins/keel-harness --strict
