#!/bin/sh
# POSIX wrapper for the shared deterministic Forever packager.
set -eu
cd "$(dirname "$0")/.."
for py in python3 python; do
    if "$py" -c 'import sys; sys.exit(sys.version_info < (3, 10))' >/dev/null 2>&1; then
        exec "$py" -I tools/package.py "$@"
    fi
done
echo 'Python 3.10 or newer is required.' >&2
exit 1
