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
