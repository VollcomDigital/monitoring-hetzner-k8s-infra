#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_DIR/terraform"

if [[ -f "$PROJECT_DIR/.env" ]]; then
  # shellcheck disable=SC1091
  source "$PROJECT_DIR/.env"
fi

if [[ -z "${HCLOUD_TOKEN:-}" ]]; then
  echo "ERROR: HCLOUD_TOKEN is not set. Define it in .env or your shell environment."
  exit 1
fi

if [[ ! -f "$TERRAFORM_DIR/terraform.tfvars" ]]; then
  echo "ERROR: $TERRAFORM_DIR/terraform.tfvars does not exist. Copy terraform.tfvars.example first."
  exit 1
fi

cd "$TERRAFORM_DIR"
terraform init -upgrade
terraform apply "$@"
