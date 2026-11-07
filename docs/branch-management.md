# Visual Math Branch and Version Management

This guide describes the branch conventions for Visual Math contributors and maintainers, following the version-line and pull-request approach used by Stroom. Branch names below are conventions; they do not imply that a branch already exists. Pull requests normally target `main`; use another base only when an issue or maintainer specifies it.

## 1. Contributor Workflow

External contributors should usually fork the repository, create a short-lived working branch from the intended pull request base in their fork, and submit a pull request to this repository. Do not push directly to shared branches.

Use a lowercase type prefix and a short topic, with words separated by hyphens. The prefix should match the change type and, where possible, the type used in the commit message. If Visual Math configures pull request template categories, these suggested categories can guide the mapping:

| Branch pattern | Suggested use | Suggested pull request category |
| --- | --- | --- |
| `feat/<topic>` | New features or user-visible capabilities | Feature |
| `fix/<topic>` | Bug fixes, including urgent fixes | Bug fix |
| `docs/<topic>` | Documentation changes | Documentation |
| `style/<topic>` | Formatting or style changes that do not affect behavior | Chore |
| `refactor/<topic>` | Code restructuring that does not change external behavior | Refactor |
| `perf/<topic>` | Performance improvements | Performance |
| `test/<topic>` | Adding or maintaining tests | Test |
| `ci/<topic>` | Continuous integration configuration | CI/build |
| `cd/<topic>` | Continuous delivery or release automation | CI/build |
| `build/<topic>` | Build system or build dependency changes | CI/build |
| `chore/<topic>` | Other maintenance work | Chore |
| `revert/<topic>` | Reverting an existing change | Category of the reverted change |

Create each working branch from the actual pull request base. The default base is `main`; use a version branch only when an issue or maintainer specifies it. State the target branch, version line, and purpose in each pull request, and meet that base branch's review and CI requirements.

## 2. Long-Lived Branches

| Branch pattern | Purpose | Management |
| --- | --- | --- |
| `main` | Default branch and current primary development line. | Changes are merged through pull requests after review and required CI checks. |
| `v<MAJOR>.<MINOR>` | Development and integration line for a minor version series. | Create when work on that series begins; managed by maintainers. |
| `release/<MAJOR>.<MINOR>` | Maintenance line for a supported older version after a newer line takes over `main`. | Create only when ongoing maintenance is needed; managed by maintainers. |

Create version development and maintenance branches only when needed; do not create branches for version series that have not started. Contributors should not create or choose long-lived branches themselves; an issue or maintainer should specify the target. Record each version line's goals, scope, and acceptance criteria in `docs/roadmap/v<MAJOR>.<MINOR>.md`. Use issues or pull requests to track individual work items. A GitHub milestone is optional; maintainers may use one to group related issues and pull requests and link to the version plan in its description.

## 3. Development and Cross-Version Fixes

- Create a separate short-lived working branch from the actual target branch for each change, then merge it through a pull request.
- Merge a fix into the target branch for the affected older version first. If a newer development line also needs it, forward-port it through a separate pull request from a short-lived branch; do not use a long-lived maintenance branch as the pull request source.
- Do not merge features intended only for a newer version into an older version branch. Adapt incompatible fixes separately and validate them on each target branch.
- Make necessary changes between long-lived branches through pull requests and resolve conflicts early rather than accumulating divergence.
- Do not push directly to `main`, version development branches, or maintenance branches. Do not force-update them or make unplanned cross-version merges.

## 4. Version Handoffs

When a `v<MAJOR>.<MINOR>` development line is ready to take over `main`:

1. Decide whether the previous version series still needs maintenance. If it does, create its `release/<MAJOR>.<MINOR>` branch from the current `main` before the handoff.
2. Complete the final required synchronization from `main` to the development line.
3. After review, CI, and merge validation, merge the development line into `main` through a pull request.
4. `main` then carries the new primary development line; any maintenance branch continues to receive necessary fixes for its older version.

## 5. Post-Merge Branch Cleanup

Visual Math currently has GitHub's automatic deletion of merged pull request branches enabled (`delete_branch_on_merge=true`). After a pull request is merged, GitHub deletes its source branch in the Visual Math repository. This setting does not delete branches in contributors' forks; fork owners can clean those up themselves. Do not use a long-lived branch as the source of a one-off pull request when it must be kept. Create a separate maintenance branch during a version handoff when needed. Branch protection rules still apply.

## 6. Release Tags

Use the `v` prefix for release tags in the form `v<MAJOR>.<MINOR>.<PATCH>`. The prefix is a common tag naming convention and is not part of the SemVer version string; the version without the prefix follows Semantic Versioning (SemVer). A tag identifies a specific release, unlike a branch that continues to change.

## 7. Repository Settings

- Keep `main` as the default branch.
- Apply appropriate protection rules to `main`, version development branches, and maintenance branches, such as requiring pull requests, review, and CI checks.
- State the target branch, version line, and purpose in each pull request, and meet the target branch's protection requirements before merging.
- Update this guide when Visual Math's version policy or GitHub branch settings change.
