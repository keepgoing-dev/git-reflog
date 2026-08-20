extends GutTest

const Repo := preload("res://addons/git-reflog/repo.gd")

var _main: String

func before_all() -> void:
    _main = KGFixture.build()

func after_all() -> void:
    KGFixture.destroy(_main)

func test_resolves_a_directory_dot_git() -> void:
    assert_eq(Repo.resolve(_main), _main.path_join(".git"))

func test_resolves_a_linked_worktree_to_the_main_git_dir() -> void:
    # A linked worktree's .git is a FILE containing `gitdir: <main>/.git/worktrees/<name>`,
    # and that directory holds a commondir file pointing back at <main>/.git. Following it
    # means pointing the game at any one worktree yields the whole repository.
    var wt_a := _main.get_base_dir().path_join("wt-a")
    assert_eq(Repo.resolve(wt_a), _main.path_join(".git"),
        "resolving a worktree must land on the common git dir, not the worktree's own")

func test_resolves_a_submodule_to_its_own_git_dir() -> void:
    var sub := _main.path_join("vendor/lib")
    assert_eq(Repo.resolve(sub), _main.path_join(".git/modules/vendor/lib"),
        "a submodule is its own repository and must not be folded into the superproject")

func test_returns_empty_for_a_non_repository() -> void:
    assert_eq(Repo.resolve("/tmp"), "")
    assert_eq(Repo.resolve("/definitely/not/here"), "")

func test_normalise_common_leaves_a_plain_git_dir_alone() -> void:
    var g := _main.path_join(".git")
    assert_eq(Repo.normalise_common(g), g, "no commondir file means nothing to follow")

func test_finds_all_four_reflog_locations() -> void:
    var reflogs := Repo.enumerate_reflogs(Repo.resolve(_main))
    var g := _main.path_join(".git")
    assert_has(reflogs, g.path_join("logs/HEAD"), "main worktree")
    assert_has(reflogs, g.path_join("worktrees/wt-a/logs/HEAD"), "first linked worktree")
    assert_has(reflogs, g.path_join("worktrees/wt-b/logs/HEAD"), "second linked worktree")
    assert_has(reflogs, g.path_join("modules/vendor/lib/logs/HEAD"), "nested submodule")
    assert_eq(reflogs.size(), 4, "and nothing else")

func test_excludes_remote_head_which_is_not_a_head_reflog() -> void:
    # Submodules contain logs/refs/remotes/origin/HEAD. A match on the filename alone,
    # or on `-name HEAD -path '*logs*'`, would wrongly include it.
    var reflogs := Repo.enumerate_reflogs(Repo.resolve(_main))
    for path in reflogs:
        assert_eq(path.get_base_dir().get_file(), "logs",
            "%s: the parent directory must be named logs" % path)

func test_matches_git_worktree_list_exactly() -> void:
    # The oracle test. git is the authority on which worktrees exist, so ask it, and
    # assert the filesystem walk agrees. Free authority in the test suite, no runtime
    # dependency on git being on PATH.
    var out: Array = []
    var code := OS.execute("git", ["-C", _main, "worktree", "list", "--porcelain"], out, true)
    assert_eq(code, 0, "git worktree list must succeed")

    var expected_worktrees: Array[String] = []
    for line in "\n".join(out).split("\n"):
        if line.begins_with("worktree "):
            expected_worktrees.append(line.substr(len("worktree ")).strip_edges())
    assert_eq(expected_worktrees.size(), 3, "main plus wt-a plus wt-b")

    # Every worktree git names must contribute exactly one reflog to our set.
    var reflogs := Repo.enumerate_reflogs(Repo.resolve(_main))
    for wt in expected_worktrees:
        var git_dir := Repo.resolve(wt)
        var own := git_dir
        # For a linked worktree, resolve() normalises to the common dir, so recover the
        # worktree's own directory from its .git file to find its private reflog.
        var dot := wt.path_join(".git")
        if FileAccess.file_exists(dot):
            var f := FileAccess.open(dot, FileAccess.READ)
            own = f.get_as_text().strip_edges().substr(len("gitdir:")).strip_edges()
            f.close()
        assert_has(reflogs, own.path_join("logs/HEAD"),
            "git named worktree %s but its reflog is missing from the walk" % wt)

    # git worktree list does not mention submodules, which is exactly why the walk exists.
    assert_has(reflogs, _main.path_join(".git/modules/vendor/lib/logs/HEAD"),
        "the submodule reflog is found by the walk and never by git worktree list")

func test_worktree_commits_are_invisible_to_the_main_reflog() -> void:
    # The fact the whole design rests on. If this ever fails, git's behaviour changed and
    # the enumeration rule must be re-derived.
    var main_log := _main.path_join(".git/logs/HEAD")
    var messages: Array[String] = []
    for e in KGReflog.read_from(main_log, 0)["entries"]:
        messages.append(e["message"])
    var joined := "\n".join(messages)
    assert_false(joined.contains("worktree a commit"),
        "a linked worktree's commit must NOT appear in the main reflog")
    assert_false(joined.contains("commit inside submodule"),
        "a submodule's commit must NOT appear in the superproject's reflog")

func test_a_new_worktree_appears_on_re_enumeration() -> void:
    var before := Repo.enumerate_reflogs(Repo.resolve(_main)).size()
    var out: Array = []
    var wt_c := _main.get_base_dir().path_join("wt-c")
    OS.execute("git", ["-C", _main, "worktree", "add", "-q", wt_c, "-b", "feature-c"], out, true)
    var after := Repo.enumerate_reflogs(Repo.resolve(_main)).size()
    assert_eq(after, before + 1, "re-enumeration picks up a worktree created while running")
