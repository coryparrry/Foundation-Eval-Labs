# Capture bundle format version 1

`format` is `foundation-evals-capture`. `formatVersion` is `1`. Unsupported versions are rejected for normalisation.

## Layout

```text
<run-id>.fevalrun/
  manifest.json
  observations.jsonl
  expectations.json                 # optional
  raw/                              # optional native bytes
  attachments/                      # optional inert files named by digest
```

`observations.jsonl` is one JSON object per line. It is this project's format, not Apple's multi-evaluation JSONL.

## Records

- **Producer:** integration version, optional bridge version, app ID, feature ID. Claims only.
- **Run:** new `runID`, optional `rerunOf`, start/end times, state `running` | `finished` | `stopped` | `cancelled`. `finished` means the plan was attempted, not that answers were correct.
- **Plan:** frozen before execution. Coordinate is `caseID` + repetition (from 1) + feature variant. One attempt per coordinate in version 1.
- **Observation:** actual input JSON, output `absent` or `returned` (including JSON `null`), execution `returned` | `threw` | `cancelled`, optional errors and checks.
- **Checks:** producer-reported. No check means not assessed. Import does not approve them.
- **Files:** relative path, byte size, SHA-256 of the preserved bytes.
- **Environment:** OS, locale, and unknowns when revision/device/model are not known.

The manifest does not contain its own digest. Importers hash the manifest bytes after copy.

## Limits

Named in `CaptureLimits.version1`: 100 planned trials, 1 concurrent trial, 0 retries, 1 MiB manifest, 5 MiB Apple JSON/transcript, 1 MiB observation line, 25 MiB bundle, 256 files, JSON depth 64, 1 MiB launcher logs, 10 minute default deadline.

## Encoding

Typed inputs and outputs are JSON values. Duplicate keys in control documents are rejected. Path members must be relative, with no `..` or absolute paths.
