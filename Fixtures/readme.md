# Launch checklist for 1.0

Claude drafted this from the open issues. {==The sequencing needs a second look==}{>>@sebo: move the migration before the announcement, we can't email people who can't log in<<}{>>@claude: moved it, and added the rollback step below<<} before anyone outside the team sees it.

## Before the announcement

1. Run the schema migration on the replica first and compare row counts.
2. Deploy the API with the feature flag **off**, then flip it for internal accounts.
3. Keep `make rollback TAG=v0.9.4` ready. It restores the previous build in about a minute.

## Announcement

- Changelog post on the blog, with the three screenshots from the design review.
- Email to the {==beta list==}{>>@sebo: only people who opted in, check the consent column first<<}.
- Pin the thread in the community forum for a week.

| Step | Owner | When |
|---|---|---|
| Migration | Claude | Tuesday 09:00 |
| Deploy | Sebo | Tuesday 10:00 |
| Email | Sebo | Wednesday |

```python
def rollback(tag: str) -> None:
    build = previous_build(tag)
    deploy(build, confirm=True)
```
