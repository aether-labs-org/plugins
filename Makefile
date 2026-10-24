.PHONY: check check-cli validate

check:
	./tests/run.sh

# kh, the keel harness CLI (cli/kh): its unit tests, then the whole suite on both engines.
check-cli:
	$(MAKE) -C cli/kh test build
	./tests/run.sh
	KEEL_ENGINE=cli ./tests/run.sh

validate:
	claude plugin validate ./plugins/keel-harness --strict
	claude plugin validate ./plugins/solutions-architect --strict
	claude plugin validate ./plugins/second-brain --strict
