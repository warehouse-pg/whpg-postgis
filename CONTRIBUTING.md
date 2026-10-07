# Contributing

We warmly welcome and greatly appreciate contributions from the
community. By participating you agree to the [code of
conduct](https://github.com/warehouse-pg/whpg-postgis/blob/whpg19/CODE-OF-CONDUCT.md).
Overall, we follow WHPG's comprehensive contribution policy. Please
refer to it [here](https://github.com/warehouse-pg/warehouse-pg/blob/main/CONTRIBUTING.md)
for details.

## Getting Started

* Fork the `whpg-postgis` repository on GitHub
* Clone the forked repository
* Follow the README to set up your environment and run the tests

## Creating a change

* Create your own feature branch (e.g. `git checkout -b
  my_feature_branch`) and make changes on this branch.
* Try and follow similar coding styles as found throughout the code
  base.
* Make commits as logical units for ease of reviewing.
* Each WarehousePG line has its own branch (`whpg6`, `whpg7` and
  `whpg19`). Base your change on the branch for the line you target,
  rebase with it often to stay in sync, and open a separate pull request
  for each line the change applies to.
* Add or update tests to cover your code. Set `GPHOME` to your
  WarehousePG installation, build with `cmake ../whpg` and `make` in a
  separate build directory, then run `make install` and the regression
  tests against a running WarehousePG cluster. See
  [`whpg/README.md`](whpg/README.md) for build and test details.
* Ensure a well written commit message as explained
  [here](https://chris.beams.io/posts/git-commit/).
* Push your local branch to the fork (e.g. `git push <your_fork>
  my_feature_branch`)

## Submitting a Pull Request

* Create a [pull request from your
  fork](https://docs.github.com/en/github/collaborating-with-issues-and-pull-requests/creating-a-pull-request-from-a-fork).
* Address PR feedback with fixup and/or squash commits:
```
git add .
git commit --fixup <commit SHA>
  -- or --
git commit --squash <commit SHA>
```
* Once approved, before merging into `whpg19` squash your fixups with:
```
git rebase -i --autosquash origin/whpg19
git push --force-with-lease $USER <my-feature-branch>
```

Your contribution will be analyzed for product fit and engineering
quality prior to merging. Your pull request is much more likely to be
accepted if it is small and focused with a clear message that conveys
the intent of your change.
