#!/usr/bin/env bash
# CI-only fallback for unavailable runner mirrors. Retain signed repository
# metadata and Ubuntu's existing Signed-By keyrings; never disable verification.
set -euo pipefail
apt_command() {
  sudo apt-get -o Acquire::Retries=1 -o Acquire::http::Timeout=15 \
    -o Acquire::https::Timeout=15 -o APT::Update::Error-Mode=any "$@"
}
if apt_command "$@"; then
  exit 0
fi
printf '%s\n' 'Runner package mirror failed; retrying official Ubuntu HTTPS archives.'
for source in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
  [[ -f "$source" ]] || continue
  sudo sed -i \
    -e 's|mirror+file:/etc/apt/apt-mirrors-security.txt|https://security.ubuntu.com/ubuntu|g' \
    -e 's|mirror+file:/etc/apt/apt-mirrors.txt|https://archive.ubuntu.com/ubuntu|g' \
    -e 's|http[s]\?://azure.archive.ubuntu.com/ubuntu|https://archive.ubuntu.com/ubuntu|g' \
    -e 's|http://archive.ubuntu.com/ubuntu|https://archive.ubuntu.com/ubuntu|g' \
    -e 's|http://security.ubuntu.com/ubuntu|https://security.ubuntu.com/ubuntu|g' \
    "$source"
done
apt_command update
if [[ "${1:-}" != update ]]; then
  apt_command "$@"
fi
