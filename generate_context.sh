#!/usr/bin/env bash
# generate_context.sh
# Creates a single code context file from a Ruby gem repo.

set -euo pipefail

OUTPUT_FILE="code_context.txt"

# Remove old file if exists
rm -f "$OUTPUT_FILE"

# Find and concatenate all .rb files, skipping vendor, spec, test, node_modules, etc.
find . \
  -type f \
  -name "*.rb" \
  ! -path "./vendor/*" \
  ! -path "./spec/*" \
  ! -path "./test/*" \
  ! -path "./node_modules/*" \
  | sort \
  | while read -r file; do
      echo "### FILE: $file" >> "$OUTPUT_FILE"
      cat "$file" >> "$OUTPUT_FILE"
      echo -e "\n\n" >> "$OUTPUT_FILE"
    done

echo "Context file created: $OUTPUT_FILE"
