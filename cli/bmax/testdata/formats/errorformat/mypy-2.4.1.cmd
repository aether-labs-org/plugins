mypy app/bad.py --show-column-numbers --show-error-codes --no-error-summary
tool version: mypy 2.4.1
2026-11-04
^(?P<file>[^:]+):(?P<line>\d+):(?P<col>\d+): (?P<severity>error|warning|note): (?P<message>.*?)(?:  \[(?P<rule>[a-z-]+)\])?$
