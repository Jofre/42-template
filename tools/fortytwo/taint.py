"""The turn-in files of a scope, their contents, and the contents a run could not vouch for.

Measured (Bazel 9.2.0, 2026-10-09; TODO.md V111): a run that is
going while a file is edited can cache a PASS for contents it never tested,
and a re-run on a still tree serves it again. So every run takes a snapshot of
its files before and after, and any content seen around a run that changed
under it, or that a save during it left as it was, is TAINTED. When a file
holds tainted content again, 42 deletes what Bazel built for its project and
runs it again with --nocache_test_results, which was measured to heal a
poisoned build as well as a poisoned result; that run vouches for the content
again.

Kept per checkout in $XDG_STATE_HOME/42/<sha1 of the checkout path>/, never in
the checkout: nothing 42 writes may end up in a commit.
"""

import hashlib
import json
import os
import re

# Files an editor writes beside the real one while saving: never a turn-in.
# Vim's swap files run .swp, .swo ... .swa, then .svz ...; .swx is its probe
# for a writable folder, and 4913 the one for a writable file. Emacs writes
# .#name and #name#.
_EDITOR_TEMP = re.compile(r"(^\..*\.s[vw][a-z]$|~$|^4913$|^\.#|^#.*#$|\.tmp$)")


def state_dir(ws, environ=None):
    env = os.environ if environ is None else environ
    base = env.get("XDG_STATE_HOME") or os.path.join(env.get("HOME", "/tmp"), ".local", "state")
    d = os.path.join(base, "42", hashlib.sha1(os.path.realpath(ws).encode()).hexdigest()[:16])
    return d


def watched_files(project, ex=None):
    """The files a scope's tests read from the student: its turn-in folders and generators.

    Listed again on every call, so a file created or deleted is seen.
    """
    roots = []
    if ex:
        t = project.turnin(ex)
        if t:
            roots.append(os.path.join(project.path, t))
        g = os.path.join(project.path, "generators", ex + ".sh")
        if os.path.isfile(g):
            roots.append(g)
    else:
        roots.append(os.path.join(project.path, "deliverable"))
        roots.append(os.path.join(project.path, "generators"))
    out = []
    for r in roots:
        if os.path.isfile(r):
            out.append(r)
            continue
        for d, dirs, files in os.walk(r):
            dirs[:] = sorted(x for x in dirs if not x.startswith("."))
            for f in sorted(files):
                if not _EDITOR_TEMP.search(f):
                    out.append(os.path.join(d, f))
    return out


def stat_key(path):
    try:
        st = os.stat(path)
    except OSError:
        return None
    return (st.st_mtime_ns, st.st_size, st.st_ino)


def stats(paths):
    """{path: (mtime, size, inode)}: what a poll compares, with no file read."""
    return {p: stat_key(p) for p in paths}


def content_hash(path):
    try:
        with open(path, "rb") as f:
            return hashlib.sha1(f.read()).hexdigest()
    except OSError:
        return None


def snapshot(paths):
    """{path: sha1 of its contents, or None if it is gone}."""
    return {p: content_hash(p) for p in paths}


class Taint:
    def __init__(self, ws, environ=None):
        self.path = os.path.join(state_dir(ws, environ), "taint.json")
        self.data = {}
        try:
            with open(self.path, encoding="utf-8") as f:
                self.data = json.load(f)
        except (OSError, ValueError):
            self.data = {}

    def save(self):
        try:
            os.makedirs(os.path.dirname(self.path), exist_ok=True)
            tmp = self.path + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(self.data, f, indent=1, sort_keys=True)
            os.replace(tmp, self.path)
        except OSError:
            pass  # the state folder cannot be written: 42 runs on, remembering nothing

    def add(self, path, digest):
        if digest is None:
            return
        seen = self.data.setdefault(path, [])
        if digest not in seen:
            seen.append(digest)
            del seen[:-8]

    def hits(self, snap):
        """The files whose current contents a run could not vouch for."""
        return sorted(p for p, h in snap.items() if h is not None and h in self.data.get(p, ()))

    def discharge(self, path, digest):
        """One content of one file, vouched for again by a rebuilt, uncached run."""
        seen = self.data.get(path, [])
        if digest in seen:
            seen.remove(digest)
        if not seen:
            self.data.pop(path, None)


def raced(before, before_stats, after, after_stats):
    """{path: the contents to taint} for a run between these snapshots and stats.

    A file whose contents changed taints what it held at both ends. A file that
    was saved during the run and holds the same contents at its end (an undo)
    taints those contents too: the build may have read what was there in
    between under their name. Measured under 42 watch, an undo 0.5 s wide:
    without this rule, 1 trial in 6 kept gcc's PASS for a file that does not
    compile; with it, 6 of 6 were honest.
    """
    out = {}
    for p in sorted(set(before) | set(after)):
        if before.get(p) != after.get(p):
            ends = [before.get(p), after.get(p)]
        elif before_stats.get(p) != after_stats.get(p):
            ends = [after.get(p)]
        else:
            continue
        ends = [h for h in ends if h is not None]
        if ends:
            out[p] = ends
    return out
