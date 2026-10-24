.PHONY: check check-cli validate

check:
	./tests/run.sh

# The keel CLI (cli/keel): its unit tests, then the whole suite on both engines.
check-cli:
	$(MAKE) -C cli/keel test build
	./tests/run.sh
	KEEL_ENGINE=cli ./tests/run.sh

validate:
	claude plugin validate ./plugins/keel-harness --strict
	claude plugin validate ./plugins/solutions-architect --strict
	claude plugin validate ./plugins/second-brain --strict
