# AGENTS

## Snapshot

- Purpose: this repo provisions and operates the self-hosted GitHub Actions
  runner infrastructure.
- Load order: load this file first. Repo-local prompt/skill overlays are not
  present yet.
- Primary docs: `README.md`, `docs/index.md`, and generated `terraform-docs`
  reference blocks.

## Working Rules

- Keep Terraform variable, output, and module descriptions complete enough for
  `terraform-docs`; generated Markdown is the canonical reference surface.
- Prefer `just` targets in docs when they exist instead of duplicating raw
  Terraform and shell commands.
- Separate runner registration flows, Vault integration notes, and operational
  runbooks from the generated Terraform reference tables.
- Do not add duplicate overview pages such as `docs/README.md`.
