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
