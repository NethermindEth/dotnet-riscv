#!/usr/bin/env python3
"""Fail if a fixup patch does not name the test that covers it.

Every patch given on the command line must have, in its message (the text
before the first "diff --git"), a line

    Regression test: <where>

where <where> is one of

    tools/tests/<dir>[/<name>]      a test of this repository; <dir> must exist
    bflat-ts:<package>/<run>        a run of the bflat-ts suite, e.g.
                                    bflat-ts:exception_handler/eh_large_frame
    none - <reason>                 nothing can test it (a build fix, a comment)

Several lines are allowed, and so are several references in one line,
separated by commas. A patch changes the code every guest is compiled
with, and a change nobody tests is found by whoever runs the guest: the line
makes the author write the test, or say why there is none.

Usage: check_patch_tests.py PATCH...
"""
import os
import re
import sys

TOP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LINE = re.compile(r"^Regression tests?:\s*(.+?)\s*$", re.M)
SUITE = re.compile(r"^bflat-ts:[a-z0-9_]+/[a-z0-9_]+$")
NONE = re.compile(r"^none\s+-\s+\S.{9,}$")


def check(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        message = ("\n" + f.read()).split("\ndiff --git ", 1)[0]
    refs = []
    for m in LINE.finditer(message):
        value = m.group(1)
        if value.startswith("none"):
            # A reason is prose: it is not a list of references.
            refs.append(value)
        else:
            refs += [r.rstrip(".") for r in re.split(r"\s*[,;]\s*", value)]
    if not refs:
        return ["no 'Regression test:' line in the message"]
    errors = []
    for ref in refs:
        if ref.startswith("tools/tests/"):
            parts = ref.split("/")
            if len(parts) < 3 or not os.path.isdir(
                    os.path.join(TOP, *parts[:3])):
                errors.append("'%s': no such directory" % "/".join(parts[:3]))
        elif not (SUITE.match(ref) or NONE.match(ref)):
            errors.append("'%s': expected tools/tests/<dir>, "
                          "bflat-ts:<package>/<run> or 'none - <reason>'"
                          % ref)
    return errors


def main():
    failed = 0
    for path in sys.argv[1:]:
        for error in check(path):
            failed += 1
            print("%s: %s" % (path, error))
    if failed:
        print("\nSee the top of tools/check_patch_tests.py for the format.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
