<!-- Release checklist. Uncomment this section if relevant.
## Checklist

- [ ] Update local tags using `git fetch --tags`.
- [ ] Check `git tag` for the latest released version.
- [ ] Depending on whether this is a major (X+1.0.0), minor (X.Y+1.0), or patch (X.Y.Z+1) release:
   - If this is a major or minor release, create a `release-X.Y` branch.
   - If this is a patch release, check out the existing `release-X.Y` branch.
- [ ] Add a change log entry to `CHANGELOG.md`.
- [ ] Look for anywhere there is a list of version numbers, such as the `Makefile`, test files, or others. In all those places, add your new version.
- [ ] Finish any other changes on this branch, such as merging in origin/master.
- [ ] Push the branch.
- [ ] Create a pull request for the branch.
- [ ] Wait for the pull request to build.
- [ ] Tag the final commit on the branch with `X.Y.Z`, for example, `1.10.2`.
- [ ] `git push origin TAG` with the tag created above.
- [ ] Wait for the [tag job](https://github.com/linz/postgresql-tableversion/actions?query=branch%3AX.Y.Z) to finish and the package to appear in the [test repository](https://packagecloud.io/app/linz/test/search?q=tableversion_X.Y.Z&filter=all&filter=all&dist=) (replace `X.Y.Z` with the tag in the links).
- [ ] Manually promote the package repository to the "prod" repository.
- [ ] Manually trigger the PR pipeline to work around a [GitHub limitation](https://docs.github.com/en/actions/using-workflows/triggering-a-workflow#triggering-a-workflow-from-a-workflow)
- [ ] Bump the Makefile version to the next patch.
-->

<!-- External issues which had to be resolved or worked around to get through this work. Uncomment this section if relevant.
## Challenges

- [X doesn't support Y](https://example.org/issues/1)
-->
