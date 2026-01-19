#!bin/bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <input-file>" >&2
  exit 1
fi

sed \
  -e 's/{{/__OPEN__/g' \
  -e 's/}}/__CLOSE__/g' \
  -e 's/__OPEN__/{{ "{{" }}/g' \
  -e 's/__CLOSE__/{{ "}}" }}/g' \
  "$1"
