#!/usr/bin/env python3
"""Turn a Robot Framework output.xml into a triage summary.

Written for CI: without it, a failed regression run says only "exit code 43" and
the only way to learn *what* broke is to download the log.html artifact. This
prints the same information as markdown and, when GITHUB_STEP_SUMMARY is set,
appends it to the job summary so the failure is readable from the run page.

Failures are grouped by error message first, because the common shape of a broken
environment is one cause wearing forty test names ("40x TENANT_NOT_PROVISIONED"
means the stack is missing its fixtures, not that forty behaviours regressed).

Always exits 0 — it reports on a run, it does not judge it. The `robot` exit code
stays the build's verdict.
"""

import argparse
import os
import re
import sys
import xml.etree.ElementTree as ET

MAX_MESSAGE = 160

# Error bodies carry a timestamp, a correlation id and assorted ids that differ on
# every single failure. Left alone they split one cause into a dozen one-row groups
# (the run this was written against reported the same TENANT_NOT_PROVISIONED body as
# "28x" and "11x" purely because the second differed in its seconds field), so they
# are masked out before grouping — never in the message that gets displayed.
VOLATILE = (
    (re.compile(r"\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:?\d{2})?"), "<ts>"),
    (re.compile(r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"), "<uuid>"),
    # Dash-less ids: traceId/correlationId are 32 hex chars, and every failure carries
    # a different one.
    (re.compile(r"\b[0-9a-fA-F]{12,}\b"), "<id>"),
    (re.compile(r"\b\d{4,}\b"), "<n>"),
)


def flatten(text):
    """Whitespace-collapsed, full-length failure message."""
    return re.sub(r"\s+", " ", (text or "").strip())


def collapse(text):
    """One-line, length-capped rendering of a Robot failure message."""
    return text[: MAX_MESSAGE - 1] + "…" if len(text) > MAX_MESSAGE else text


def cause_key(message):
    """Full message with run-specific noise masked, so identical causes group together.

    Must run on the untruncated text: truncation alone cuts a timestamp mid-field and
    leaves two halves of one cause looking like two different errors.
    """
    for pattern, placeholder in VOLATILE:
        message = pattern.sub(placeholder, message)
    return message


def md_escape(text):
    return text.replace("|", "\\|")


def collect(node, path, failures):
    for suite in node.findall("suite"):
        collect(suite, path + [suite.get("name", "")], failures)
    for test in node.findall("test"):
        status = test.find("status")
        if status is None or status.get("status") != "FAIL":
            continue
        failures.append(
            {
                # The full nesting is mostly "Tests & E2E & E2E/E2E/..." scaffolding;
                # the last two levels are what identifies the suite to a human.
                "suite": " / ".join(p for p in path[-2:] if p),
                "test": test.get("name", ""),
                "tags": [t.text or "" for t in test.findall("tag")],
                "raw": flatten(status.text),
                "message": collapse(flatten(status.text)),
            }
        )


def totals(root):
    """Read the pass/fail/skip counts Robot itself computed, not a recount."""
    stat = root.find("./statistics/total/stat")
    if stat is None:
        return None
    return {k: int(stat.get(k, 0)) for k in ("pass", "fail", "skip")}


def render(title, counts, failures, max_tests, artifact):
    out = [f"## {title}", ""]

    if counts:
        verdict = "❌ FAILED" if counts["fail"] else "✅ PASSED"
        out.append(
            f"{verdict} — **{counts['pass']} passed**, "
            f"**{counts['fail']} failed**, {counts['skip']} skipped"
        )
    else:
        out.append("⚠️ Could not read totals from output.xml (run may have crashed early).")
    out.append("")

    if not failures:
        return "\n".join(out) + "\n"

    # Grouped first: one broken dependency shows up here as a single fat row.
    groups = {}
    for f in failures:
        groups.setdefault(cause_key(f["raw"]), []).append(f)
    out += ["### Failures by cause", "", "| # | Error |", "|---:|---|"]
    for group in sorted(groups.values(), key=len, reverse=True):
        out.append(f"| {len(group)} | {md_escape(group[0]['message']) or '(no message)'} |")
    out += ["", f"### Failed tests ({len(failures)})", "", "| Suite | Test | Error |", "|---|---|---|"]
    for f in failures[:max_tests]:
        out.append(
            f"| {md_escape(f['suite'])} | {md_escape(f['test'])} | {md_escape(f['message'])} |"
        )
    if len(failures) > max_tests:
        out.append(f"| … | _{len(failures) - max_tests} more_ | |")
    out.append("")
    if artifact:
        out.append(f"Full trace: download the **{artifact}** artifact and open `log.html`.")
        out.append("")
    return "\n".join(out) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output_xml", help="path to Robot Framework's output.xml")
    parser.add_argument("--title", default="Robot Framework results")
    parser.add_argument("--artifact", default="", help="artifact name holding log.html")
    parser.add_argument("--max-tests", type=int, default=40)
    args = parser.parse_args()

    if not os.path.exists(args.output_xml):
        # A missing output.xml is itself a finding: robot never got far enough to
        # write one (bad CLI options, unreachable data source, killed process).
        summary = f"## {args.title}\n\n⚠️ No `{args.output_xml}` — Robot did not produce results.\n"
    else:
        root = ET.parse(args.output_xml).getroot()
        failures = []
        collect(root, [], failures)
        summary = render(args.title, totals(root), failures, args.max_tests, args.artifact)

    sys.stdout.write(summary)
    step_summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if step_summary:
        with open(step_summary, "a", encoding="utf-8") as handle:
            handle.write(summary)


if __name__ == "__main__":
    main()
