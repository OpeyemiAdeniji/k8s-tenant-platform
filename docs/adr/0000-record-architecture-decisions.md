# 0000. Record architecture decisions

- Status: accepted
- Date: YYYY-MM-DD

## Context

Design choices are easy to forget and hard to justify later. Without a record, nobody (including future me) knows why something was built a certain way or which alternatives were rejected.

## Decision

Significant decisions are recorded as short Markdown files in `docs/adr/`, numbered sequentially (`0001-title.md`), using the template in `adr-template.md`. They go through the same pull request review as code.

## Consequences

- The reasoning behind the project is visible next to the code.
- Each decision costs a few minutes to write.
- Superseded decisions are not deleted. Their status changes to "superseded by NNNN".
