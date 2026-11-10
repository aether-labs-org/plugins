"""Command-line entry point; `bin/sb` runs it through `bin/sb-python`."""
import os
import sys

# Like the hooks: do not rely on the script directory being on sys.path (PYTHONSAFEPATH, -P).
sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))

from sb.cli import main  # noqa: E402

if __name__ == "__main__":
    sys.exit(main())
