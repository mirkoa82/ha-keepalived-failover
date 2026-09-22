#!/usr/bin/env bash
set -euo pipefail

EXPECTED_IP="${1:?Errore: IP fisico atteso non indicato}"

MATCHES="$(
    ip -o -4 addr show scope global \
    | awk -v expected="${EXPECTED_IP}" '$4 ~ ("^" expected "/") { print $2 "|" $4 }'
)"

MATCH_COUNT="$(printf '%s\n' "${MATCHES}" | sed '/^$/d' | wc -l)"

if [ "${MATCH_COUNT}" -ne 1 ]; then
    echo "ERRORE: trovati ${MATCH_COUNT} match per IP ${EXPECTED_IP}." >&2
    echo "Indirizzi IPv4 globali disponibili:" >&2
    ip -o -4 addr show scope global >&2
    exit 1
fi

INTERFACE="${MATCHES%%|*}"
ADDRESS="${MATCHES#*|}"

echo "${INTERFACE}|${ADDRESS}"
