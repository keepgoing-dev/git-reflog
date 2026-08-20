# Reading "what work happened here" out of a git HEAD reflog.
#
# The qualifying filter is a correctness requirement, not an optimisation. `git checkout`
# and `git pull` move HEAD without the user writing anything, so treating all HEAD
# movement as work would pay coins for switching branches.
class_name KGReflog
extends RefCounted

## `git commit --amend` appends a fresh qualifying entry every time it runs, with no new
## work behind it. Counting it would make a shell loop into a coin printer.
const AMEND_PREFIX := "commit (amend)"

## A reflog line is `<old> <new> <name> <email> <unix-ts> <tz>\t<message>`.
##
## Returns `{"ts": int, "message": String}`, or `{}` for any line that carries no message.
## A linked worktree's first reflog line genuinely has no tab, so `{}` is a normal result.
static func parse_line(line: String) -> Dictionary:
    var tab := line.find("\t")
    if tab == -1:
        return {}
    var header := line.substr(0, tab)
    var message := line.substr(tab + 1)
    var fields := header.split(" ", false)
    # Author names contain spaces, so the timestamp is found by counting from the right:
    # the last field is the timezone and the one before it is the timestamp.
    if fields.size() < 6:
        return {}
    var ts_field: String = fields[fields.size() - 2]
    if not ts_field.is_valid_int():
        return {}
    return {"ts": ts_field.to_int(), "message": message}

## Does this entry represent the user producing something?
##
## Counted: commit, commit (initial), commit (amend), commit (merge).
## Ignored: checkout, pull, fast-forward merge, reset, clone, rebase replays.
static func qualifies(message: String) -> bool:
    return message.begins_with("commit")

## Does this entry earn coins? Everything that qualifies except an amend.
static func is_income(message: String) -> bool:
    return qualifies(message) and not message.begins_with(AMEND_PREFIX)

## Read entries appended since `offset`.
##
## Returns `{"entries": Array, "offset": int, "restarted": bool}`.
##
## Three hazards are handled here, and each one is silent if you get it wrong:
##
## 1. `git gc` prunes the reflog, leaving the file shorter than the stored offset. The
##    read restarts from zero and reports `restarted`, so the caller filters on timestamp
##    rather than paying for the same work twice.
## 2. Git may be caught mid-append. Only bytes up to the last newline are consumed, so a
##    half-written line is read again next time rather than corrupting the offset forever.
## 3. Offsets are in BYTES. Commit messages routinely contain multibyte characters, and a
##    character offset drifts from the true position the first time one appears.
static func read_from(path: String, offset: int) -> Dictionary:
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null:
        # A repository that has been moved or unmounted is not an error worth surfacing
        # to someone who wanted to look at a pixel city.
        return {"entries": [], "offset": offset, "restarted": false}

    var size := f.get_length()
    var restarted := false
    var start := offset
    if size < offset:
        start = 0
        restarted = true

    f.seek(start)
    var tail := f.get_buffer(size - start)
    f.close()

    # Find the last newline by byte, not by character.
    var last_nl := -1
    for i in range(tail.size() - 1, -1, -1):
        if tail[i] == 10:
            last_nl = i
            break
    if last_nl == -1:
        return {"entries": [], "offset": start, "restarted": restarted}

    var complete := tail.slice(0, last_nl).get_string_from_utf8()
    var entries: Array = []
    for line in complete.split("\n"):
        var e := parse_line(line)
        if not e.is_empty():
            entries.append(e)

    return {"entries": entries, "offset": start + last_nl + 1, "restarted": restarted}
