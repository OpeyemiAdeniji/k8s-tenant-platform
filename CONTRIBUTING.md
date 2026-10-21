# Working agreement

This project follows a trunk-based workflow with short-lived branches.

## Workflow

1. Open or pick an issue.
2. Branch from `main`: `feat/short-name`, `fix/short-name`, `docs/short-name`. Aim to merge within a day or two.
3. Commit small and often using [Conventional Commits](https://www.conventionalcommits.org/): `feat: add disk threshold check`.
4. Push and open a pull request. Fill in the template. Wait for CI.
5. Squash-merge, delete the branch.

`main` is protected: no direct pushes, CI must pass.

## Setup

```bash
python3 -m venv .venv && source .venv/bin/activate
make setup
```

This installs the pre-commit hooks (formatting checks, secret scanning, commit message check).

## Releases

Tag with semantic versions (`v0.1.0` for a working skeleton, `v1.0.0` when complete), update `CHANGELOG.md`, and create a GitHub Release from the tag.

## Decisions

Record significant design choices in `docs/adr/` using `adr-template.md`.
