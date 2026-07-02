#!/usr/bin/env python3
"""Summarize Vivado OOC reports into a small Markdown file."""

import argparse
import re
from pathlib import Path
from typing import Dict, List, Optional


def find_first(patterns: List[str], text: str) -> str:
    for pattern in patterns:
        match = re.search(pattern, text, flags=re.MULTILINE)
        if match:
            return match.group(1).strip()
    return "not found"


def relative_display_path(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(Path.cwd().resolve()))
    except ValueError:
        return path.name


def parse_design_timing_summary(text: str) -> Optional[Dict[str, str]]:
    in_summary = False
    for line in text.splitlines():
        if "Design Timing Summary" in line:
            in_summary = True
            continue
        if not in_summary:
            continue
        match = re.match(
            r"^\s*([-+]?\d+(?:\.\d+)?)\s+"
            r"([-+]?\d+(?:\.\d+)?)\s+\d+\s+\d+\s+"
            r"([-+]?\d+(?:\.\d+)?)\s+"
            r"([-+]?\d+(?:\.\d+)?)\s+",
            line,
        )
        if match:
            return {
                "wns": match.group(1),
                "tns": match.group(2),
                "whs": match.group(3),
                "ths": match.group(4),
            }
    return None


def parse_timing(report_dir: Path) -> Dict[str, str]:
    timing_path = report_dir / "timing_summary.rpt"
    if not timing_path.exists():
        return {"timing_report": "missing"}

    text = timing_path.read_text(errors="ignore")
    table = parse_design_timing_summary(text)
    if table is not None:
        table["timing_report"] = timing_path.name
        return table

    return {
        "timing_report": timing_path.name,
        "wns": find_first([r"^\s*WNS\(ns\)\s*:\s*([-+0-9.]+)", r"^\s*WNS\s+([-+0-9.]+)"], text),
        "tns": find_first([r"^\s*TNS\(ns\)\s*:\s*([-+0-9.]+)", r"^\s*TNS\s+([-+0-9.]+)"], text),
        "whs": find_first([r"^\s*WHS\(ns\)\s*:\s*([-+0-9.]+)", r"^\s*WHS\s+([-+0-9.]+)"], text),
        "ths": find_first([r"^\s*THS\(ns\)\s*:\s*([-+0-9.]+)", r"^\s*THS\s+([-+0-9.]+)"], text),
    }


def parse_utilization(report_dir: Path) -> Dict[str, str]:
    util_path = report_dir / "utilization.rpt"
    if not util_path.exists():
        return {"utilization_report": "missing"}

    text = util_path.read_text(errors="ignore")
    rows = {}
    for line in text.splitlines():
        if not line.lstrip().startswith("|"):
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if len(cells) < 5:
            continue
        name = cells[0].rstrip("*")
        if name in {"Slice LUTs", "Slice Registers", "CLB LUTs", "CLB Registers",
                    "Block RAM Tile", "DSPs"}:
            rows[name] = {
                "used": cells[1],
                "available": cells[-2],
                "util": cells[-1],
            }

    return {
        "utilization_report": util_path.name,
        "slice_luts": format_util(rows.get("Slice LUTs") or rows.get("CLB LUTs")),
        "slice_registers": format_util(rows.get("Slice Registers") or rows.get("CLB Registers")),
        "block_ram_tiles": format_util(rows.get("Block RAM Tile")),
        "dsps": format_util(rows.get("DSPs")),
    }


def format_util(row: Optional[Dict[str, str]]) -> str:
    if row is None:
        return "not found"
    return f"{row['used']} / {row['available']} ({row['util']}%)"


def write_summary(report_dir: Path, output_path: Path) -> None:
    timing = parse_timing(report_dir)
    util = parse_utilization(report_dir)

    lines = [
        "# Vivado OOC Summary",
        "",
        f"Report directory: `{relative_display_path(report_dir)}`",
        "",
        "## Timing",
        "",
        f"- WNS: `{timing.get('wns', 'not found')}` ns",
        f"- TNS: `{timing.get('tns', 'not found')}` ns",
        f"- WHS: `{timing.get('whs', 'not found')}` ns",
        f"- THS: `{timing.get('ths', 'not found')}` ns",
        "",
        "## Utilization",
        "",
        f"- Slice LUTs: `{util.get('slice_luts', 'not found')}`",
        f"- Slice Registers: `{util.get('slice_registers', 'not found')}`",
        f"- Block RAM Tiles: `{util.get('block_ram_tiles', 'not found')}`",
        f"- DSPs: `{util.get('dsps', 'not found')}`",
        "",
    ]
    output_path.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report_dir", type=Path, help="Directory containing Vivado OOC .rpt files.")
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=None,
        help="Markdown output path. Defaults to <report_dir>/summary.md.",
    )
    args = parser.parse_args()

    report_dir = args.report_dir.resolve()
    output_path = args.output.resolve() if args.output else report_dir / "summary.md"
    write_summary(report_dir, output_path)
    print(f"Wrote {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
