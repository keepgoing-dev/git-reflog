# git-reflog

Reads git HEAD reflogs from Godot 4. Two files, no dependencies, no network.

This is the complete set of code that KeepGoing products use to look at your
repositories. It is published so you can read it, and it is consumed by those
products as a submodule, so what you read is what runs.

## What it reads

Only HEAD reflogs: `logs/HEAD`, one per worktree. Never your file contents,
never your diffs, never a remote.

A commit made in a linked worktree does **not** appear in `.git/logs/HEAD`,
and neither does a commit made in a submodule. So enumeration finds all four
locations:

    <gitdir>/logs/HEAD                                  main worktree
    <gitdir>/worktrees/<name>/logs/HEAD                 linked worktrees
    <gitdir>/modules/<nested/path>/logs/HEAD            submodules, any depth
    <gitdir>/modules/<path>/worktrees/<name>/logs/HEAD  worktrees of submodules

## What it does not do

No network calls of any kind. No subprocesses. No writes to your repository:
no hooks are installed and nothing inside `.git` is modified. Uninstalling
leaves nothing behind.

## Use

```gdscript
var git_dir := KGRepo.resolve("/path/to/project")
for reflog in KGRepo.enumerate_reflogs(git_dir):
    var result := KGReflog.read_from(reflog, 0)
    for entry in result["entries"]:
        if KGReflog.is_income(entry["message"]):
            print(entry["ts"], " ", entry["message"])
```

`read_from` takes a byte offset and returns the next one, so repeated calls
cost only what was appended. It handles `git gc` truncating the file, git
being caught mid-append, and multibyte commit messages.

## Tests

Requires [GUT](https://github.com/bitwes/Gut). `tests/` includes an oracle
test that asks `git worktree list --porcelain` for the truth and asserts the
filesystem walk agrees.

The tests drive `tools/fake-repo.sh` from the consuming repository, which
builds a fixture with two linked worktrees and a nested submodule.

MIT licensed.
