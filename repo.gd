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
