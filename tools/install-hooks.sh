#!/bin/sh
# Points git at tools/git-hooks so the gate runs before each push.
cd "$(dirname "$0")/.." && git config core.hooksPath tools/git-hooks && echo "pre-push gate installed (git config core.hooksPath tools/git-hooks)"
