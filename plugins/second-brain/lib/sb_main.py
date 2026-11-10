"""Command-line entry point; `bin/sb` runs it through `bin/sb-python`."""
import sys

from sb.cli import main

if __name__ == "__main__":
    sys.exit(main())
