# Agent instructions

## Before making changes

If the working tree is clean (no staged or unstaged changes), sync with `origin/main` before starting work:

```bash
git fetch origin
git pull --ff-only origin main
```

Skip this when local changes already exist, so work in progress is not disrupted.

## Git commits and pull requests

Use [Conventional Commits](https://www.conventionalcommits.org/) for every commit message, PR title, and PR description.

### Commit messages

Format:

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

Rules:

- Use imperative mood in the description (`add`, `fix`, `update` — not `added` / `fixes`)
- Keep the subject line concise (about 72 characters or less)
- Do not end the subject with a period
- Prefer a scope when it clarifies the change (e.g. `feat(wall): …`, `fix(auth): …`)
- Use `BREAKING CHANGE:` in the footer (or `!` after the type/scope) for breaking changes

Common types:

| Type | Use when |
| --- | --- |
| `feat` | A new feature |
| `fix` | A bug fix |
| `docs` | Documentation only |
| `style` | Formatting / whitespace (no logic change) |
| `refactor` | Code change that is neither a fix nor a feature |
| `perf` | Performance improvement |
| `test` | Adding or updating tests |
| `build` | Build system or dependencies |
| `ci` | CI configuration |
| `chore` | Maintenance that does not fit the above |

Examples:

```
feat(wall): add ambient parallax layer
fix(render): prevent flicker on resize
docs: document wallpaper export flow
refactor(ui): extract timeline scrubber
```

### Pull request titles

PR titles must follow the same Conventional Commits subject format:

```
<type>[optional scope]: <description>
```

Examples:

```
feat(wall): support custom color palettes
fix(ci): correct Xcode scheme name
```

### Pull request descriptions

Structure the PR body around the change, still aligned with Conventional Commits intent:

```markdown
## Summary
- <why / what, in 1–3 bullets; match the PR type>

## Test plan
- [ ] <how to verify>
```

Guidelines:

- Lead with intent that matches the title type (`feat`, `fix`, etc.)
- Call out breaking changes explicitly (e.g. a `BREAKING CHANGE` section or note)
- Keep the summary focused on why the change exists, not a file-by-file dump
- Include a concrete test plan checklist

### Completion workflow

For every completed piece of work that changes the repository:

1. Commit the intended changes using a Conventional Commit.
2. Push the branch and open a draft pull request immediately after the work is complete.
3. Include a concrete, reproducible test plan in the pull request description using Markdown checkboxes.
4. Validate every test-plan item against the actual result. Change `[ ]` to `[x]` only when that item passes; leave failed or unverified items unchecked and document the reason.
5. Wait for all required CI/CD checks to finish successfully and confirm that every test-plan item is checked.
6. Once the test plan and CI/CD checks pass, mark the draft pull request ready and merge it immediately. Do not leave a passing pull request open without merging it.
