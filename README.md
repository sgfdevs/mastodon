# SGF Devs Mastodon Instance

## Initial Setup

```bash
export AWS_ACCESS_KEY_ID=""
export AWS_SECRET_ACCESS_KEY=""
export RESTIC_REPOSITORY_PREFIX=""
export RESTIC_PASSWORD=""
restic -r $RESTIC_REPOSITORY_PREFIX/mastodon init
```
