# git-repo-clean

`git-repo-clean` is a small set of Bash utilities for maintaining Git repositories by automatically cleaning up **obsolete tags** and **merged branches**.

The repository currently contains two scripts:

- **Tag cleanup script** — removes old numeric release tags based on count and age.
- **Merged branch cleanup script** — removes remote branches that have already been merged into the default branch using different merge strategies.

Both scripts are designed to be:
- safe by default (dry-run mode),
- fully automatable,
- suitable for scheduled or CI-based maintenance.

---

## Tag Cleanup Script

### Purpose

The tag cleanup script is intended to manage repositories that use **numeric release tags** (for example `0001`, `0002`, …) for deployments or releases.

Over time, such repositories accumulate a large number of tags. This script keeps the repository clean by **retaining only the most recent tags** while safely removing older ones.

### How It Works

The script operates only on tags that match a strict numeric format:

```
^[0-9]{4}$
```

All other tags are ignored and reported separately for manual review.

The cleanup logic consists of **two independent safety layers**:

1. **Tag count retention**
   - Only the last *N* numeric tags are eligible to remain.
   - Older tags become deletion candidates.

2. **Age-based protection**
   - Even if a tag is older by count, it will **not be deleted** if the commit it points to is newer than a specified number of months.
   - The age check is based on the commit timestamp, not the tag creation time.

A tag is deleted **only if both conditions are met**:
- it exceeds the retained tag count, and
- it is older than the configured age threshold.

### Key Characteristics

- Uses commit timestamps, not tag metadata.
- Supports both lightweight and annotated tags.
- Cross-platform (Linux and macOS).
- Dry-run by default.
- Fully non-interactive and CI-safe.
- Explicit reporting of:
   - kept tags,
   - deleted tags,
   - tags skipped due to age,
   - tags skipped due to invalid format.

This script is well-suited for scheduled maintenance jobs and automated release pipelines.

---

## Merged Branch Cleanup Script

### Purpose

The merged branch cleanup script removes **remote branches** that are no longer needed because their changes have already been integrated into the default branch (usually `main` or `master`).

It is specifically designed for **GitHub-based workflows** and supports multiple merge strategies.

### Merge Detection Strategies

The script determines whether a branch is safe to delete using several independent checks:

1. **Git merge-base (classic merge)**
   - Detects branches that were merged using a normal merge commit or fast-forward.

2. **GitHub Pull Request inspection**
   - Uses the GitHub CLI (`gh`) to detect pull requests associated with a branch.
   - If a pull request exists and its state is `MERGED`, the branch is considered safe to delete.
   - This allows detection of squash and rebase merges.

### Optional Issue Tracker Safety Layer (CSV)

As an additional safeguard, the script can use an **external issue tracker export**.

If a file named:

```
issues.csv
```

is present in the working directory, the script applies an extra validation layer.

#### Expected CSV Properties

- The first column contains a **numeric task ID**.
- The third column contains the **task status**.
- A branch name may start with a **five-digit task ID prefix**.

#### Behavior with `issues.csv`

- If a branch is merged but the task is not found or not `Closed`, the branch is preserved.
- Such branches are placed into a separate safety category for manual review.
- If `issues.csv` is not present, this safety layer is skipped.

### Output and Safety

The script produces a concise summary including:

- total remote branches checked,
- protected branches skipped,
- branches deleted via Git and PR detection,
- branches preserved by issue safety checks.

By default, the script runs in **dry-run mode**.

---

## Summary

`git-repo-clean` provides a practical and conservative approach to repository hygiene:

- aggressive enough to reduce clutter,
- cautious enough to avoid accidental data loss,
- transparent and auditable in its decisions.

It is intended to be used as an internal maintenance tool rather than a one-off cleanup script.
