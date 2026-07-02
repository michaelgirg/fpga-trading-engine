#!/usr/bin/env bash
# Run a routed Vivado implementation timing matrix for HFT-class FPGA parts.
#
# Optional environment variables:
#   VIVADO_SETTINGS                  Path to settings64.sh to source before running.
#   MARKET_PARSER_PARTS              Space-separated Vivado part names.
#   MARKET_PARSER_TOPS               Space-separated top modules.
#   MARKET_PARSER_PERIODS            Space-separated clock periods in ns.
#   MARKET_PARSER_SYNTH_DIRECTIVE    Vivado synth_design directive.
#   MARKET_PARSER_PLACE_DIRECTIVE    Vivado place_design directive.
#   MARKET_PARSER_ROUTE_DIRECTIVE    Vivado route_design directive.
#   MARKET_PARSER_PHYS_OPT_DIRECTIVE Vivado phys_opt_design directive, or None.
#   MARKET_PARSER_IMPL_MATRIX_DIR    Output directory for this matrix run.

set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

if [ -n "${VIVADO_SETTINGS:-}" ]; then
    if [ ! -f "$VIVADO_SETTINGS" ]; then
        echo "ERROR: VIVADO_SETTINGS does not exist: $VIVADO_SETTINGS" >&2
        exit 1
    fi
    # shellcheck disable=SC1090
    . "$VIVADO_SETTINGS"
fi

if ! command -v vivado >/dev/null 2>&1; then
    echo "ERROR: vivado is not on PATH. Source Vivado settings64.sh first or set VIVADO_SETTINGS." >&2
    exit 1
fi

PARTS=${MARKET_PARSER_PARTS:-"xcu50-fsvh2104-2-e"}
TOPS=${MARKET_PARSER_TOPS:-"market_parser_100g_strategy_impl_harness"}
PERIODS=${MARKET_PARSER_PERIODS:-"3.102 2.500 2.350"}
SYNTH_DIRECTIVE=${MARKET_PARSER_SYNTH_DIRECTIVE:-"RuntimeOptimized"}
PLACE_DIRECTIVE=${MARKET_PARSER_PLACE_DIRECTIVE:-"Explore"}
ROUTE_DIRECTIVE=${MARKET_PARSER_ROUTE_DIRECTIVE:-"Explore"}
PHYS_OPT_DIRECTIVE=${MARKET_PARSER_PHYS_OPT_DIRECTIVE:-"Explore"}
RUN_ROOT=${MARKET_PARSER_IMPL_MATRIX_DIR:-"$REPO_ROOT/build/hft_impl_matrix/$(date +%Y%m%d_%H%M%S)"}
SUMMARY="$RUN_ROOT/summary.tsv"

mkdir -p "$RUN_ROOT"
printf "part\ttop\tperiod_ns\tfreq_mhz\twns_ns\ttns_ns\twhs_ns\tths_ns\tluts\tregisters\tbram_tiles\tdsps\tstatus\treport_dir\n" > "$SUMMARY"

parse_timing() {
    awk '
        found && $1 ~ /^[-+]?[0-9.]+$/ {
            print $1 "\t" $2 "\t" $5 "\t" $6
            exit
        }
        /Design Timing Summary/ { found=1 }
    ' "$1"
}

parse_util_row() {
    local report=$1
    local primary=$2
    local secondary=$3
    awk -F'|' -v primary="$primary" -v secondary="$secondary" '
        function trim(s) {
            gsub(/^[ \t]+|[ \t]+$/, "", s)
            return s
        }
        {
            name = trim($2)
            gsub(/\*/, "", name)
            if (name == primary || name == secondary) {
                used = trim($3)
                avail = trim($(NF - 2))
                util = trim($(NF - 1))
                print used " / " avail " (" util "%)"
                exit
            }
        }
    ' "$report"
}

timing_status() {
    local rc=$1
    local wns=$2
    local tns=$3

    if [ "$rc" -ne 0 ]; then
        echo "VIVADO_FAIL"
    elif [ -z "$wns" ] || [ -z "$tns" ]; then
        echo "NO_TIMING"
    elif awk -v wns="$wns" -v tns="$tns" 'BEGIN { exit !((wns + 0.0) >= 0.0 && (tns + 0.0) == 0.0) }'; then
        echo "PASS"
    else
        echo "TIMING_FAIL"
    fi
}

for part in $PARTS; do
    for top in $TOPS; do
        for period in $PERIODS; do
            dest="$RUN_ROOT/$part/${top}_${period}ns"
            report_dir="$dest/reports"
            impl_dir="$REPO_ROOT/build/vivado_impl/$top"
            mkdir -p "$dest"

            case "$impl_dir" in
                "$REPO_ROOT"/build/vivado_impl/*)
                    rm -rf "$impl_dir"
                    ;;
                *)
                    echo "ERROR: refusing to clean unexpected path: $impl_dir" >&2
                    exit 1
                    ;;
            esac

            echo "RUN_IMPL part=$part top=$top period=${period}ns synth=$SYNTH_DIRECTIVE place=$PLACE_DIRECTIVE route=$ROUTE_DIRECTIVE phys_opt=$PHYS_OPT_DIRECTIVE"
            vivado -mode batch -source "$REPO_ROOT/tools/run_vivado_impl.tcl" \
                -tclargs "$top" "$part" "$period" "$SYNTH_DIRECTIVE" "$PLACE_DIRECTIVE" "$ROUTE_DIRECTIVE" "$PHYS_OPT_DIRECTIVE" \
                > "$dest/vivado.log" 2>&1
            rc=$?

            if [ -d "$impl_dir" ]; then
                mv "$impl_dir" "$report_dir"
            fi

            wns=""
            tns=""
            whs=""
            ths=""
            luts="missing"
            regs="missing"
            bram="missing"
            dsps="missing"

            if [ -f "$report_dir/timing_summary.rpt" ]; then
                timing=$(parse_timing "$report_dir/timing_summary.rpt")
                wns=$(printf "%s" "$timing" | awk '{print $1}')
                tns=$(printf "%s" "$timing" | awk '{print $2}')
                whs=$(printf "%s" "$timing" | awk '{print $3}')
                ths=$(printf "%s" "$timing" | awk '{print $4}')
            fi

            if [ -f "$report_dir/utilization.rpt" ]; then
                luts=$(parse_util_row "$report_dir/utilization.rpt" "CLB LUTs" "Slice LUTs")
                regs=$(parse_util_row "$report_dir/utilization.rpt" "CLB Registers" "Slice Registers")
                bram=$(parse_util_row "$report_dir/utilization.rpt" "Block RAM Tile" "Block RAM Tile")
                dsps=$(parse_util_row "$report_dir/utilization.rpt" "DSPs" "DSPs")
            fi

            freq=$(awk -v p="$period" 'BEGIN { if ((p + 0.0) > 0.0) printf "%.1f", 1000.0 / p; else printf "n/a" }')
            status=$(timing_status "$rc" "$wns" "$tns")

            printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
                "$part" "$top" "$period" "$freq" "${wns:-missing}" "${tns:-missing}" \
                "${whs:-missing}" "${ths:-missing}" "$luts" "$regs" "$bram" "$dsps" \
                "$status" "$report_dir" >> "$SUMMARY"
        done
    done
done

echo
echo "Summary written to $SUMMARY"
if command -v column >/dev/null 2>&1; then
    column -t -s "$(printf '\t')" "$SUMMARY"
else
    cat "$SUMMARY"
fi
