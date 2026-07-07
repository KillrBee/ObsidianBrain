#!/usr/bin/env bash
# uninstall.sh — thin shim over install.sh --uninstall.
exec "$(cd "$(dirname "$0")" && pwd)/install.sh" --uninstall "$@"
