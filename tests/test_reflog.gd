extends GutTest

const R := preload("res://addons/git-reflog/reflog.gd")

func test_parses_a_normal_commit_line() -> void:
    var line := "0000000000000000000000000000000000000000 59302b1 t <t@t> 1787194136 +0700\tcommit (initial): root commit"
    var e := R.parse_line(line)
    assert_eq(e.get("ts"), 1787194136)
    assert_eq(e.get("message"), "commit (initial): root commit")

func test_splits_on_the_first_tab_not_the_last() -> void:
    # A commit message can contain tabs. The header never does.
    var line := "aaa bbb t <t@t> 1700000000 +0000\tcommit: fix\tthe\tthing"
    var e := R.parse_line(line)
    assert_eq(e.get("message"), "commit: fix\tthe\tthing")

func test_reads_timestamp_from_the_right_so_spaces_in_names_are_safe() -> void:
    var line := "aaa bbb Ada Lovelace <ada@example.com> 1700000001 +0100\tcommit: hello"
    var e := R.parse_line(line)
    assert_eq(e.get("ts"), 1700000001)

func test_tolerates_the_tabless_first_line_of_a_worktree_reflog() -> void:
    # Verified against real git: a linked worktree's first reflog line has no tab
    # and no message at all. This is normal, not corruption.
    var line := "0000000000000000000000000000000000000000 59302b1 t <t@t> 1787194136 +0700"
    assert_eq(R.parse_line(line), {}, "a message-less line yields no entry")

func test_ignores_blank_and_malformed_lines() -> void:
    assert_eq(R.parse_line(""), {})
    assert_eq(R.parse_line("garbage\tcommit: x"), {}, "too few header fields")
    assert_eq(R.parse_line("a b c d notanumber +0000\tcommit: x"), {}, "unparsable timestamp")

func test_qualifies_only_commits() -> void:
    for m in ["commit: x", "commit (initial): x", "commit (amend): x", "commit (merge): x"]:
        assert_true(R.qualifies(m), "%s should qualify" % m)
    for m in ["checkout: moving from a to b", "pull: Fast-forward",
              "merge feature: Fast-forward", "reset: moving to HEAD",
              "clone: from /tmp/x", "rebase (pick): x", "rebase (finish): returning"]:
        assert_false(R.qualifies(m), "%s must not qualify" % m)

func test_amend_qualifies_but_is_not_income() -> void:
    # git commit --amend appends a fresh qualifying entry every run with no new work,
    # so a shell loop would print coins. The original commit already paid.
    assert_true(R.qualifies("commit (amend): x"))
    assert_false(R.is_income("commit (amend): x"))

func test_other_commits_are_income() -> void:
    for m in ["commit: x", "commit (initial): x", "commit (merge): x"]:
        assert_true(R.is_income(m), "%s should be income" % m)
    assert_false(R.is_income("checkout: moving"), "a checkout is never income")
