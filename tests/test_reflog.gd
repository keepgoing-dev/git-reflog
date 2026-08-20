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

var _tmp: String

func before_each() -> void:
    _tmp = "user://test_reflog_%d.log" % randi()

func after_each() -> void:
    DirAccess.remove_absolute(ProjectSettings.globalize_path(_tmp))

func _write(text: String) -> String:
    var f := FileAccess.open(_tmp, FileAccess.WRITE)
    f.store_string(text)
    f.close()
    return ProjectSettings.globalize_path(_tmp)

func _line(ts: int, msg: String) -> String:
    return "aaa bbb t <t@t> %d +0000\t%s\n" % [ts, msg]

func test_reads_all_entries_from_offset_zero() -> void:
    var p := _write(_line(100, "commit: one") + _line(200, "commit: two"))
    var r := R.read_from(p, 0)
    assert_eq(r["entries"].size(), 2)
    assert_eq(r["entries"][0]["ts"], 100)
    assert_false(r["restarted"])

func test_reads_only_new_entries_on_second_call() -> void:
    var first := _line(100, "commit: one")
    var p := _write(first)
    var r1 := R.read_from(p, 0)
    assert_eq(r1["entries"].size(), 1)
    _write(first + _line(200, "commit: two"))
    var r2 := R.read_from(p, r1["offset"])
    assert_eq(r2["entries"].size(), 1, "only the appended line is returned")
    assert_eq(r2["entries"][0]["ts"], 200)

func test_offset_is_a_byte_offset_not_a_character_offset() -> void:
    # A commit message with multibyte characters makes character counting wrong, and the
    # symptom is a permanently misaligned offset that silently drops or duplicates work.
    var first := _line(100, "commit: héllo 🚀 wörld")
    var p := _write(first)
    var r1 := R.read_from(p, 0)
    assert_eq(r1["offset"], first.to_utf8_buffer().size(),
        "offset must equal the byte length of what was consumed")
    _write(first + _line(200, "commit: next"))
    var r2 := R.read_from(p, r1["offset"])
    assert_eq(r2["entries"].size(), 1)
    assert_eq(r2["entries"][0]["message"], "commit: next")

func test_restarts_when_gc_truncated_the_file() -> void:
    var p := _write(_line(100, "commit: one") + _line(200, "commit: two"))
    var stale_offset := 10_000
    var r := R.read_from(p, stale_offset)
    assert_true(r["restarted"], "a file shorter than the stored offset means gc pruned it")
    assert_eq(r["entries"].size(), 2, "everything is re-read so the caller can filter by ts")

func test_does_not_consume_a_partially_written_line() -> void:
    # git may be caught mid-append. Consuming a half line would corrupt the offset forever.
    var complete := _line(100, "commit: one")
    var p := _write(complete + "aaa bbb t <t@t> 200 +0000\tcommit: half-writ")
    var r := R.read_from(p, 0)
    assert_eq(r["entries"].size(), 1, "only the complete line is returned")
    assert_eq(r["offset"], complete.to_utf8_buffer().size(), "offset stops at the last newline")

func test_missing_file_is_not_an_error() -> void:
    var r := R.read_from("/definitely/not/here/logs/HEAD", 0)
    assert_eq(r["entries"], [])
    assert_eq(r["offset"], 0, "offset is unchanged so a remounted repo resumes correctly")

func test_empty_file_yields_nothing() -> void:
    var p := _write("")
    var r := R.read_from(p, 0)
    assert_eq(r["entries"], [])
    assert_eq(r["offset"], 0)
