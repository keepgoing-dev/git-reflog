# Drives tools/fake-repo.sh from a test. Kept separate so both test scripts share it and
# so the public repository stays self-contained.
class_name KGFixture
extends RefCounted

static func _script(name: String) -> String:
    return ProjectSettings.globalize_path("res://../tools/%s" % name)

static func _run(exe: String, args: Array) -> String:
    var out: Array = []
    var code := OS.execute(exe, args, out, true)
    assert(code == 0, "%s %s failed: %s" % [exe, args, out])
    return "\n".join(out).strip_edges()

## Builds the fixture and returns the main worktree path.
static func build() -> String:
    var dir := _run("mktemp", ["-d", "-t", "ctropolis"])
    return _run(_script("fake-repo.sh"), ["build", dir])

static func commits(worktree: String, n: int) -> void:
    _run(_script("fake-repo.sh"), ["commits", worktree, str(n)])

static func amends(worktree: String, n: int) -> void:
    _run(_script("fake-repo.sh"), ["amends", worktree, str(n)])

## The fixture's parent temp directory holds main/, lib/, wt-a/ and wt-b/.
static func destroy(main: String) -> void:
    _run("rm", ["-rf", main.get_base_dir()])
