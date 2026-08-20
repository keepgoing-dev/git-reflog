# What counts as a repository, and where its reflogs actually live.
class_name KGRepo
extends RefCounted

## Resolve a folder the user picked to the git directory whose reflogs we read.
##
## Returns "" when the path is not a repository. Both linked worktrees and submodules
## store `.git` as a FILE rather than a directory.
static func resolve(project_path: String) -> String:
    var dot := project_path.path_join(".git")

    if DirAccess.dir_exists_absolute(dot):
        return normalise_common(dot)

    if not FileAccess.file_exists(dot):
        return ""

    var f := FileAccess.open(dot, FileAccess.READ)
    if f == null:
        return ""
    var text := f.get_as_text().strip_edges()
    f.close()

    if not text.begins_with("gitdir:"):
        return ""
    var target := text.substr(len("gitdir:")).strip_edges()
    if target.is_relative_path():
        target = project_path.path_join(target).simplify_path()
    return normalise_common(target)

## Follow a linked worktree's `commondir` back to the repository's shared git directory.
##
## `<main>/.git/worktrees/<name>/commondir` holds a relative path (`../..`). A submodule's
## git directory has no commondir, so it is returned unchanged and stays its own repository.
static func normalise_common(git_dir: String) -> String:
    var commondir := git_dir.path_join("commondir")
    if not FileAccess.file_exists(commondir):
        return git_dir
    var f := FileAccess.open(commondir, FileAccess.READ)
    if f == null:
        return git_dir
    var rel := f.get_as_text().strip_edges()
    f.close()
    if rel.is_empty():
        return git_dir
    if rel.is_relative_path():
        return git_dir.path_join(rel).simplify_path()
    return rel

## Every HEAD reflog belonging to this repository, sorted.
##
## One rule: a path counts when its parent directory is named `logs` and its filename is
## `HEAD`. That single rule covers all four locations:
##
##   <gitdir>/logs/HEAD                                  main worktree
##   <gitdir>/worktrees/<name>/logs/HEAD                 linked worktrees
##   <gitdir>/modules/<nested/path>/logs/HEAD            submodules, any depth
##   <gitdir>/modules/<path>/worktrees/<name>/logs/HEAD  worktrees of submodules
##
## The parent-is-`logs` condition is required rather than pedantic: submodules also hold
## `logs/refs/remotes/origin/HEAD`, which a filename match would wrongly include.
##
## Traversal is explicit rather than a blind recursive sweep, because `objects/` in a large
## repository holds thousands of directories that can never contain a reflog.
static func enumerate_reflogs(git_dir: String) -> Array[String]:
    var out: Array[String] = []
    _collect(git_dir, out)
    out.sort()
    return out

static func _collect(git_dir: String, out: Array[String]) -> void:
    var head := git_dir.path_join("logs").path_join("HEAD")
    if FileAccess.file_exists(head):
        out.append(head)

    # Each linked worktree keeps its own HEAD reflog. A commit made in one never appears
    # in the main worktree's reflog, so missing these misses the work entirely.
    var wt_root := git_dir.path_join("worktrees")
    for name in _subdirs(wt_root):
        var wt_head := wt_root.path_join(name).path_join("logs").path_join("HEAD")
        if FileAccess.file_exists(wt_head):
            out.append(wt_head)

    _collect_modules(git_dir.path_join("modules"), out)

## Submodule paths nest: a submodule at `vendor/lib` lives at `modules/vendor/lib`, so a
## one-level glob is wrong. Descend until a directory is itself a git directory.
static func _collect_modules(dir: String, out: Array[String]) -> void:
    for name in _subdirs(dir):
        var child := dir.path_join(name)
        if FileAccess.file_exists(child.path_join("HEAD")):
            # A real git directory: recurse so its own worktrees and nested submodules
            # are found too.
            _collect(child, out)
        else:
            # An intermediate path component, such as `vendor` above.
            _collect_modules(child, out)

static func _subdirs(dir: String) -> PackedStringArray:
    if not DirAccess.dir_exists_absolute(dir):
        return PackedStringArray()
    return DirAccess.get_directories_at(dir)
