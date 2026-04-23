# AGENTS

## Purpose

This repository provisions and operates the self-hosted GitHub Actions runner
infrastructure.

## Documentation Standards

- Keep `README.md` as the GitHub entrypoint and `docs/index.md` as the docs
  landing page.
- Do not add duplicate overview pages such as `docs/README.md`.
- Keep Terraform variable, output, and module descriptions complete enough for
  `terraform-docs`; generated Markdown is the canonical reference surface.
- Prefer `just` targets in docs when they exist instead of duplicating raw
  Terraform and shell commands.
- Separate runner registration flows, Vault integration notes, and operational
  runbooks from the generated Terraform reference tables.
