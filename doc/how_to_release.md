1. Set $version to final in Makefile (drop the "dev" suffix)
2. Set date and final $version in CHANGELOG.md
3. Commit
4. Tag $version
5. Publish to PGXN (make dist and upload to https://manager.pgxn.org/upload)
6. if $version ends in 0, then: branch release-$major.$minor
7. Set new target version (in both master and release branch if any)
8. Push commits, tags and branches (if any made)
