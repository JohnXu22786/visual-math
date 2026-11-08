# Branching and Pull Request Workflow

This guide keeps VisualMath work easy to review and safe to integrate. Use GitHub issues to track work, one branch and linked worktree per implementation unit, and one focused pull request (PR) per unit.

## Branch names

Use this format for new branches:

```text
<type>/<task-id>--<short-kebab-description>
```

- `<type>` describes the work. Use `feature`, `fix`, `docs`, `test`, `refactor`, `ci`, `chore`, or `release`.
- `<task-id>` is the issue number or a short, unique work-item identifier, written in lowercase kebab case. Keep it stable across the branch, PR, and related commits.
- The double hyphen (`--`) separates the task ID from the short description.
- Keep the description concise and use lowercase words separated by single hyphens.

Examples:

```text
feature/42--settings-theme
fix/57--stale-formula-paste
docs/visualmath-branching-policy--define-branch-workflow
```

Use the canonical types above for new branches. Older branches and PRs may use names such as `feat` or `bugfix`; leave existing names intact, and use `feature` or `fix` for new work.

## Choose a base branch

- **Independent work:** start from the latest `main` and open the PR against `main`.
- **Dependent work:** stack a branch only when its issue explicitly depends on another unit. Start it from the exact prerequisite branch and open its PR against that same branch. Do not guess dependencies from issue order.
- After the prerequisite PR merges, update the dependent branch to the latest `main`, change its PR base to `main`, and verify the diff contains only the dependent unit's changes. Rerun the checks required for the updated PR.

Avoid unrelated changes in a branch. If a task grows beyond its issue's scope, split the additional work into a separate issue and branch.

## Use a linked worktree for each unit

Use a separate Git linked worktree for each task branch. This keeps concurrent tasks isolated and prevents one branch's files from leaking into another task.

Before starting work, confirm the worktree uses the intended branch and base. Do not make task changes directly on `main`. When work is merged, remove its worktree and local branch only after confirming no uncommitted work remains and the branch is no longer needed.

## Pull requests

Open one focused PR per issue or implementation unit. Use a clear title in this form:

```text
<type>(<area>): <short summary>
```

For example: `feature(settings): add persistent theme selection`.

In the PR description:

- Explain the user-visible result and the main implementation choices.
- Link the tracking issue; use `Closes #<number>` when the PR completes that issue.
- List the relevant validation performed and any platform or compatibility limits.
- Keep the PR target aligned with the branch's base: `main` for independent work, or the exact prerequisite branch for stacked work.

Keep commits focused and descriptive. Follow the repository's contribution guidance and the checks GitHub reports as required for the target branch. Required checks and branch protection can change; check the current repository settings and PR status rather than assuming a fixed list.

## Safe Git practices

- Fetch the latest base before creating a branch and review `git status` before committing.
- Do not commit directly to `main` or bypass required reviews and checks.
- Do not force-push shared branches. If a rewrite is needed, coordinate with the other contributors using that branch and follow repository policy.
- Resolve conflicts by preserving the current base branch's intent as well as the task's requirements, then review the full PR diff.
- After merge, verify the PR is merged and the change is present on its target branch before cleaning up local references.

## Suggested branches for the VisualMath roadmap

The following names reflect the current issue split. They are examples only; use them if and when the corresponding implementation plan is approved. The application work remains unapproved until then.

| Issue | Suggested branch | Base / dependency |
| --- | --- | --- |
| #29 Home and Settings navigation shell | `feature/visualmath-nav-shell--home-settings-navigation` | `main` |
| #30 Settings and persistent theme | `feature/visualmath-theme-settings--persistent-theme` | #29 branch |
| #31 Update checks | `feature/visualmath-update-check--platform-update-check` | #30 branch |
| #32 Open-source licenses and version display | `feature/visualmath-licenses-version--license-version-details` | #30 branch; can proceed alongside #31 after #30 |

Localization is deferred from this roadmap and should be tracked separately if it is scheduled later.
