#!/bin/bash
###############################################################################
#  BIDS Conversion Script — Multi-Modal with Optional Source Cleanup
#
#  Supports: anat, func, dwi, fmap, perf, pet, meg, eeg, ieeg, micr, motion
#
#  Usage:
#    ./bids_convert.sh [OPTIONS]
#
#  Options:
#    -i, --input DIR       Source data root directory (required)
#    -o, --output DIR      BIDS output directory (default: ./BIDS)
#    -c, --config FILE     Folder-to-modality mapping config (default: auto-generated)
#    -d, --delete-source   Delete source DICOMs after successful conversion
#    -s, --sourcedata      Copy originals into BIDS sourcedata/ before converting
#    -n, --dry-run         Show what would happen without doing anything
#    -p, --parallel N      Run N conversions in parallel (default: 1)
#    -v, --verbose         Verbose output
#    -h, --help            Show this help
#
###############################################################################
set -euo pipefail
IFS=$'\n\t'

# ─────────────────────────────────────────────────────────────────────────────
# GLOBALS & DEFAULTS
# ─────────────────────────────────────────────────────────────────────────────
VERSION="2.1.0"
SCRIPT_NAME="$(basename "$0")"
INPUT_DIR=""
OUTPUT_DIR="./BIDS"
CONFIG_FILE=""
DELETE_SOURCE=false
COPY_SOURCEDATA=false
DRY_RUN=false
PARALLEL=1
VERBOSE=false
LOG_FILE=""
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
ERRORS=0
WARNINGS=0
CONVERTED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ─────────────────────────────────────────────────────────────────────────────
# LOGGING
# ─────────────────────────────────────────────────────────────────────────────
log()      { echo -e "${GREEN}[INFO]${NC}  $*"; [ -n "$LOG_FILE" ] && echo "[INFO]  $*" >> "$LOG_FILE"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC}  $*" >&2; ((WARNINGS++)) || true; [ -n "$LOG_FILE" ] && echo "[WARN]  $*" >> "$LOG_FILE"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $*" >&2; ((ERRORS++)) || true; [ -n "$LOG_FILE" ] && echo "[ERROR] $*" >> "$LOG_FILE"; }
log_dbg()  { $VERBOSE && echo -e "${CYAN}[DEBUG]${NC} $*"; [ -n "$LOG_FILE" ] && echo "[DEBUG] $*" >> "$LOG_FILE"; }
log_dry()  { echo -e "${BLUE}[DRY-RUN]${NC} $*"; }

# ─────────────────────────────────────────────────────────────────────────────
# HELP / USAGE
# ─────────────────────────────────────────────────────────────────────────────
usage() {
cat << USAGE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ${SCRIPT_NAME} v${VERSION} — Multi-Modal BIDS Converter
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  USAGE:
    $SCRIPT_NAME -i <source_dir> [OPTIONS]

  REQUIRED:
    -i, --input DIR         Source data root directory

  OPTIONS:
    -o, --output DIR        BIDS output directory        [default: ./BIDS]
    -c, --config FILE       Folder-to-modality mapping   [default: auto-detect]
    -d, --delete-source     Delete source files after successful conversion
    -s, --sourcedata        Archive originals in BIDS sourcedata/
    -n, --dry-run           Preview without executing
    -p, --parallel N        Parallel conversion jobs     [default: 1]
    -v, --verbose           Verbose logging
    -h, --help              Show this help

  EXAMPLES:
    # Basic conversion
    $SCRIPT_NAME -i /data/raw -o /data/BIDS

    # Dry-run with verbose output
    $SCRIPT_NAME -i /data/raw -o /data/BIDS -n -v

    # Convert, archive originals, then delete source
    $SCRIPT_NAME -i /data/raw -o /data/BIDS -s -d

    # Use custom mapping config
    $SCRIPT_NAME -i /data/raw -o /data/BIDS -c my_mapping.conf

    # Run 4 subjects in parallel
    $SCRIPT_NAME -i /data/raw -o /data/BIDS -p 4

  CONFIG FILE FORMAT (one rule per line):
    # <source_folder_pattern>  <bids_modality>  <bids_suffix>  [task_label]
    SAG                        anat             T1w
    AX_T2                      anat             T2w
    FLAIR*                     anat             FLAIR
    DTI*                       dwi              dwi
    BOLD_REST*                 func             bold           rest
    BOLD_NBACK*                func             bold           nback
    FIELD_MAP_PH*              fmap             phasediff
    FIELD_MAP_MAG*             fmap             magnitude
    ASL*                       perf             asl
    PET*                       pet              pet

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
USAGE
exit 0
}

# ─────────────────────────────────────────────────────────────────────────────
# ARGUMENT PARSING
# ─────────────────────────────────────────────────────────────────────────────
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -i|--input)         INPUT_DIR="$2"; shift 2 ;;
            -o|--output)        OUTPUT_DIR="$2"; shift 2 ;;
            -c|--config)        CONFIG_FILE="$2"; shift 2 ;;
            -d|--delete-source) DELETE_SOURCE=true; shift ;;
            -s|--sourcedata)    COPY_SOURCEDATA=true; shift ;;
            -n|--dry-run)       DRY_RUN=true; shift ;;
            -p|--parallel)      PARALLEL="$2"; shift 2 ;;
            -v|--verbose)       VERBOSE=true; shift ;;
            -h|--help)          usage ;;
            *)
                log_err "Unknown option: $1"
                echo "Use -h for help."
                exit 1
                ;;
        esac
    done

    if [ -z "$INPUT_DIR" ]; then
        log_err "Input directory is required. Use -i <dir>."
        exit 1
    fi

    if [ ! -d "$INPUT_DIR" ]; then
        log_err "Input directory does not exist: $INPUT_DIR"
        exit 1
    fi

    INPUT_DIR="$(cd "$INPUT_DIR" && pwd)"
    mkdir -p "$OUTPUT_DIR"
    OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
    LOG_FILE="${OUTPUT_DIR}/bids_conversion_${TIMESTAMP}.log"

    # Validate --parallel value
    if ! [[ "$PARALLEL" =~ ^[1-9][0-9]*$ ]]; then
        log_err "--parallel must be a positive integer, got: $PARALLEL"
        exit 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# DEPENDENCY CHECKS
# ─────────────────────────────────────────────────────────────────────────────
check_dependencies() {
    local missing=()

    if ! command -v dcm2niix &>/dev/null; then
        missing+=("dcm2niix")
    fi

    if ! command -v python3 &>/dev/null; then
        missing+=("python3")
    fi

    if ! command -v jq &>/dev/null; then
        log_warn "jq not found — JSON editing will fall back to python3"
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        log_err "Missing required tools: ${missing[*]}"
        log_err "Install with:"
        log_err "  sudo apt-get install dcm2niix python3 jq"
        log_err "  or: conda install -c conda-forge dcm2niix"
        exit 1
    fi

    log "dcm2niix version: $(dcm2niix --version 2>&1 | head -1 || echo 'unknown')"
}

# ─────────────────────────────────────────────────────────────────────────────
# DEFAULT FOLDER-TO-MODALITY MAPPING
#
# Each entry:  PATTERN | BIDS_MODALITY | BIDS_SUFFIX | TASK (optional)
#
# Patterns use bash globbing (case-insensitive matching applied separately).
# ─────────────────────────────────────────────────────────────────────────────
declare -a MAPPING_PATTERNS=()
declare -a MAPPING_MODALITIES=()
declare -a MAPPING_SUFFIXES=()
declare -a MAPPING_TASKS=()

load_default_mapping() {
    # ── Anatomical ──────────────────────────────────
    add_mapping "SAG*T1*"         "anat"  "T1w"          ""
    add_mapping "*T1*SAG*"        "anat"  "T1w"          ""
    add_mapping "*T1W*"           "anat"  "T1w"          ""
    add_mapping "*T1*"            "anat"  "T1w"          ""
    add_mapping "*MPRAGE*"        "anat"  "T1w"          ""
    add_mapping "*SPGR*"          "anat"  "T1w"          ""
    add_mapping "*BRAVO*"         "anat"  "T1w"          ""
    add_mapping "SAG"             "anat"  "T1w"          ""

    add_mapping "*T2W*"           "anat"  "T2w"          ""
    add_mapping "*T2*AX*"         "anat"  "T2w"          ""
    add_mapping "*T2*SAG*"        "anat"  "T2w"          ""
    add_mapping "*T2_SPACE*"      "anat"  "T2w"          ""

    add_mapping "*FLAIR*"         "anat"  "FLAIR"        ""
    add_mapping "*T2_FLAIR*"      "anat"  "FLAIR"        ""

    add_mapping "*T1RHO*"         "anat"  "T1rho"        ""
    add_mapping "*T2STAR*"        "anat"  "T2starw"      ""
    add_mapping "*SWI*"           "anat"  "T2starw"      ""

    add_mapping "*PDW*"           "anat"  "PDw"          ""
    add_mapping "*PD_*"           "anat"  "PDw"          ""

    add_mapping "*ANGIO*"         "anat"  "angio"        ""
    add_mapping "*TOF*"           "anat"  "angio"        ""

    # ── Diffusion ───────────────────────────────────
    add_mapping "*DTI*"           "dwi"   "dwi"          ""
    add_mapping "*DWI*"           "dwi"   "dwi"          ""
    add_mapping "*DIFF*"          "dwi"   "dwi"          ""
    add_mapping "*HARDI*"         "dwi"   "dwi"          ""
    add_mapping "*DSI*"           "dwi"   "dwi"          ""

    # ── Functional ──────────────────────────────────
    add_mapping "*REST*BOLD*"     "func"  "bold"         "rest"
    add_mapping "*BOLD*REST*"     "func"  "bold"         "rest"
    add_mapping "*RESTING*"       "func"  "bold"         "rest"
    add_mapping "*RS_FMRI*"       "func"  "bold"         "rest"

    add_mapping "*NBACK*"         "func"  "bold"         "nback"
    add_mapping "*MOTOR*"         "func"  "bold"         "motor"
    add_mapping "*LANGUAGE*"      "func"  "bold"         "language"
    add_mapping "*EMOTION*"       "func"  "bold"         "emotion"
    add_mapping "*GAMBLING*"      "func"  "bold"         "gambling"
    add_mapping "*SOCIAL*"        "func"  "bold"         "social"
    add_mapping "*WM*BOLD*"       "func"  "bold"         "wm"

    add_mapping "*BOLD*"          "func"  "bold"         "unknown"
    add_mapping "*FMRI*"          "func"  "bold"         "unknown"
    add_mapping "*EPI*BOLD*"      "func"  "bold"         "unknown"

    # ── Fieldmaps ───────────────────────────────────
    add_mapping "*FIELD*MAP*PH*"  "fmap"  "phasediff"    ""
    add_mapping "*PHASE*DIFF*"    "fmap"  "phasediff"    ""
    add_mapping "*FIELD*MAP*MAG*" "fmap"  "magnitude"    ""
    add_mapping "*MAGNITUDE*"     "fmap"  "magnitude"    ""
    add_mapping "*B0*MAP*"        "fmap"  "fieldmap"     ""
    add_mapping "*TOPUP*AP*"      "fmap"  "epi"          ""
    add_mapping "*TOPUP*PA*"      "fmap"  "epi"          ""
    add_mapping "*SE*FIELD*"      "fmap"  "epi"          ""
    add_mapping "*DISTORTION*"    "fmap"  "epi"          ""
    add_mapping "*PEPOLAR*"       "fmap"  "epi"          ""

    # ── Perfusion ───────────────────────────────────
    add_mapping "*ASL*"           "perf"  "asl"          ""
    add_mapping "*PCASL*"         "perf"  "asl"          ""
    add_mapping "*PASL*"          "perf"  "asl"          ""
    add_mapping "*CBF*"           "perf"  "cbf"          ""
    add_mapping "*PERFUSION*"     "perf"  "asl"          ""

    # ── PET ─────────────────────────────────────────
    add_mapping "*PET*"           "pet"   "pet"          ""
    add_mapping "*FDG*"           "pet"   "pet"          ""
    add_mapping "*AMYLOID*"       "pet"   "pet"          ""
    add_mapping "*TAU*PET*"       "pet"   "pet"          ""

    # ── MEG ─────────────────────────────────────────
    add_mapping "*MEG*"           "meg"   "meg"          ""

    # ── EEG ─────────────────────────────────────────
    add_mapping "*EEG*"           "eeg"   "eeg"          ""
    add_mapping "*SCALP*EEG*"     "eeg"   "eeg"          ""

    # ── iEEG ────────────────────────────────────────
    add_mapping "*IEEG*"          "ieeg"  "ieeg"         ""
    add_mapping "*ECOG*"          "ieeg"  "ieeg"         ""
    add_mapping "*SEEG*"          "ieeg"  "ieeg"         ""
    add_mapping "*DEPTH*ELEC*"    "ieeg"  "ieeg"         ""

    # ── Microscopy ──────────────────────────────────
    add_mapping "*MICR*"          "micr"  "TEM"          ""
    add_mapping "*HISTOLOGY*"     "micr"  "BF"           ""

    # ── Motion ──────────────────────────────────────
    add_mapping "*MOTION*"        "motion" "motion"      ""
    add_mapping "*IMU*"           "motion" "motion"      ""
    add_mapping "*ACCEL*"         "motion" "motion"      ""
}

add_mapping() {
    MAPPING_PATTERNS+=("$1")
    MAPPING_MODALITIES+=("$2")
    MAPPING_SUFFIXES+=("$3")
    MAPPING_TASKS+=("$4")
}

# ─────────────────────────────────────────────────────────────────────────────
# LOAD CONFIG FILE (overrides defaults)
# ─────────────────────────────────────────────────────────────────────────────
load_config_file() {
    local cfg="$1"

    if [ ! -f "$cfg" ]; then
        log_err "Config file not found: $cfg"
        exit 1
    fi

    # Clear defaults
    MAPPING_PATTERNS=()
    MAPPING_MODALITIES=()
    MAPPING_SUFFIXES=()
    MAPPING_TASKS=()

    while IFS= read -r line || [ -n "$line" ]; do
        # Skip comments and blanks
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue

        local pattern modality suffix task
        read -r pattern modality suffix task <<< "$line"

        if [ -z "$pattern" ] || [ -z "$modality" ] || [ -z "$suffix" ]; then
            log_warn "Skipping malformed config line: $line"
            continue
        fi

        add_mapping "$pattern" "$modality" "$suffix" "${task:-}"
    done < "$cfg"

    log "Loaded ${#MAPPING_PATTERNS[@]} mapping rules from $cfg"
}

# ─────────────────────────────────────────────────────────────────────────────
# MATCH SOURCE FOLDER TO BIDS MODALITY
# Returns via global vars: MATCHED_MODALITY, MATCHED_SUFFIX, MATCHED_TASK
# ─────────────────────────────────────────────────────────────────────────────
MATCHED_MODALITY=""
MATCHED_SUFFIX=""
MATCHED_TASK=""

match_folder() {
    local folder_name="$1"
    local folder_upper="${folder_name^^}"  # uppercase for case-insensitive matching

    MATCHED_MODALITY=""
    MATCHED_SUFFIX=""
    MATCHED_TASK=""

    for i in "${!MAPPING_PATTERNS[@]}"; do
        local pattern_upper="${MAPPING_PATTERNS[$i]^^}"

        # Use bash extended globbing for matching
        # shellcheck disable=SC2254
        if [[ "$folder_upper" == $pattern_upper ]]; then
            MATCHED_MODALITY="${MAPPING_MODALITIES[$i]}"
            MATCHED_SUFFIX="${MAPPING_SUFFIXES[$i]}"
            MATCHED_TASK="${MAPPING_TASKS[$i]}"
            log_dbg "Matched '$folder_name' → $MATCHED_MODALITY / $MATCHED_SUFFIX (task=$MATCHED_TASK)"
            return 0
        fi
    done

    return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# COUNT FILES IN A DIRECTORY (DICOM or otherwise)
# ─────────────────────────────────────────────────────────────────────────────
count_source_files() {
    find "$1" -maxdepth 1 -type f \
        \( -name "*.dcm" -o -name "*.DCM" \
           -o -name "*.IMA" -o -name "*.ima" \
           -o -name "*.img" -o -name "*.hdr" \
           -o -name "MR.*" -o -name "CT.*" -o -name "PT.*" \
           -o -regex '.*/[0-9]+$' \
           -o -regex '.*/IM-[0-9]+-[0-9]+$' \
        \) 2>/dev/null | wc -l
}

has_source_files() {
    local dir="$1"
    local count
    count=$(count_source_files "$dir")

    if [ "$count" -gt 0 ]; then
        return 0
    fi

    # Fallback: any file at all (dcm2niix can detect DICOM without extensions)
    local any_files
    any_files=$(find "$dir" -maxdepth 1 -type f | wc -l)
    [ "$any_files" -gt 0 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# BUILD BIDS FILENAME
# ─────────────────────────────────────────────────────────────────────────────
build_bids_filename() {
    local sub_label="$1"
    local ses_label="$2"    # empty string if no session
    local modality="$3"
    local suffix="$4"
    local task="$5"
    local run="$6"          # empty or run number
    local folder_name="${7:-}"

    local fname="${sub_label}"

    [ -n "$ses_label" ] && fname="${fname}_${ses_label}"

    case "$modality" in
        func)
            [ -n "$task" ] && fname="${fname}_task-${task}" ;;
        perf)
            [ -n "$task" ] && fname="${fname}_task-${task}" ;;
        pet)
            # PET uses tracer label (trc-) rather than task
            [ -n "$task" ] && fname="${fname}_trc-${task}" ;;
        meg|eeg|ieeg)
            [ -n "$task" ] && fname="${fname}_task-${task}" ;;
    esac

    # Run number
    [ -n "$run" ] && fname="${fname}_run-$(printf '%02d' "$run")"

    # Phase-encoding direction for fieldmap EPIs
    if [ "$modality" = "fmap" ] && [ "$suffix" = "epi" ]; then
        local dir_upper="${folder_name^^}"
        if [[ "$dir_upper" == *"AP"* ]]; then
            fname="${fname}_dir-AP"
        elif [[ "$dir_upper" == *"PA"* ]]; then
            fname="${fname}_dir-PA"
        elif [[ "$dir_upper" == *"LR"* ]]; then
            fname="${fname}_dir-LR"
        elif [[ "$dir_upper" == *"RL"* ]]; then
            fname="${fname}_dir-RL"
        fi
    fi

    fname="${fname}_${suffix}"
    echo "$fname"
}

# ─────────────────────────────────────────────────────────────────────────────
# CONVERT A SINGLE SOURCE FOLDER
# ─────────────────────────────────────────────────────────────────────────────
convert_folder() {
    local source_dir="$1"
    local output_dir="$2"
    local bids_filename="$3"
    local modality="$4"

    if $DRY_RUN; then
        log_dry "dcm2niix -z y -f '$bids_filename' -o '$output_dir' '$source_dir'"
        return 0
    fi

    mkdir -p "$output_dir"

    # FIX: Store dcm2niix logs in a dedicated logs/ subdirectory instead of
    # deleting them — useful for post-hoc QC and debugging failed conversions.
    local log_dir="${OUTPUT_DIR}/logs"
    mkdir -p "$log_dir"
    local dcm2niix_log="${log_dir}/dcm2niix_${bids_filename}.log"

    # Run dcm2niix
    if dcm2niix -z y -b y -ba y -f "$bids_filename" -o "$output_dir" "$source_dir" \
        > "$dcm2niix_log" 2>&1; then
        log "  ✅ Converted → ${output_dir}/${bids_filename}.nii.gz"
    else
        log_err "  dcm2niix failed for $source_dir (see $dcm2niix_log)"
        return 1
    fi

    # ── Handle multiple outputs (dcm2niix appends _a, _b, etc.) ──
    local nifti_count
    nifti_count=$(ls "${output_dir}/${bids_filename}"*.nii.gz 2>/dev/null | wc -l)

    if [ "$nifti_count" -eq 0 ]; then
        log_warn "  No NIfTI output produced for $source_dir"
        return 1
    elif [ "$nifti_count" -gt 1 ]; then
        log_warn "  Multiple NIfTI outputs ($nifti_count) — renaming as runs"
        local run_num=1
        for nii_file in "${output_dir}/${bids_filename}"*.nii.gz; do
            local base="${nii_file%.nii.gz}"
            local run_tag="_run-$(printf '%02d' $run_num)"
            local suffix_part="${bids_filename##*_}"
            local prefix_part="${bids_filename%_*}"
            local new_name="${prefix_part}${run_tag}_${suffix_part}"

            for ext in .nii.gz .json .bval .bvec; do
                local old_file="${base}${ext}"
                local new_file="${output_dir}/${new_name}${ext}"
                if [ -f "$old_file" ]; then
                    mv "$old_file" "$new_file"
                    log_dbg "  Renamed: $(basename "$old_file") → $(basename "$new_file")"
                fi
            done
            ((run_num++)) || true
        done
    fi

    # ── Validate DWI outputs ──
    if [ "$modality" = "dwi" ]; then
        local has_bval=false has_bvec=false
        ls "${output_dir}/${bids_filename}"*.bval &>/dev/null && has_bval=true
        ls "${output_dir}/${bids_filename}"*.bvec &>/dev/null && has_bvec=true

        if ! $has_bval || ! $has_bvec; then
            log_warn "  Missing bval/bvec for DWI — manual creation may be needed"
        else
            log_dbg "  bval/bvec files present"
        fi
    fi

    ((CONVERTED++)) || true
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# POST-CONVERSION JSON ENRICHMENT
# FIX: Pass shell variables as env vars rather than interpolating them
#      directly into the Python source, which breaks on values containing
#      single quotes (e.g. folder names like "O'Brien").
# ─────────────────────────────────────────────────────────────────────────────
enrich_json() {
    local json_file="$1"
    local modality="$2"
    local task="$3"

    [ ! -f "$json_file" ] && return 0

    if $DRY_RUN; then
        log_dry "Would enrich JSON: $json_file"
        return 0
    fi

    BIDS_JSON_FILE="$json_file" BIDS_MODALITY="$modality" BIDS_TASK="$task" \
    python3 << 'PYEOF' 2>/dev/null || true
import json, sys, os

json_file = os.environ['BIDS_JSON_FILE']
modality  = os.environ['BIDS_MODALITY']
task      = os.environ['BIDS_TASK']

try:
    with open(json_file, 'r') as f:
        data = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    sys.exit(0)

# Add TaskName for functional / perf / electrophysiology data (BIDS requirement)
if modality in ('func', 'perf', 'meg', 'eeg', 'ieeg') and task:
    data.setdefault('TaskName', task)

# Propagate RepetitionTime from vendor-specific field when missing (func)
if modality == 'func' and 'RepetitionTime' not in data:
    if 'RepetitionTimeExcitation' in data:
        data['RepetitionTime'] = data['RepetitionTimeExcitation']

# Add IntendedFor placeholder for fieldmaps — must be filled in manually.
# bids-validator will flag an empty list, so we leave the field absent rather
# than adding an empty placeholder that causes a validation error.
# Callers are warned by generate_report() instead.

with open(json_file, 'w') as f:
    json.dump(data, f, indent=4, sort_keys=False)
PYEOF
}

# ─────────────────────────────────────────────────────────────────────────────
# ARCHIVE SOURCE DATA
# ─────────────────────────────────────────────────────────────────────────────
archive_sourcedata() {
    local source="$1"
    local sub_label="$2"
    local ses_label="$3"
    local folder_name="$4"

    local archive_dir="${OUTPUT_DIR}/sourcedata/${sub_label}"
    [ -n "$ses_label" ] && archive_dir="${archive_dir}/${ses_label}"
    archive_dir="${archive_dir}/${folder_name}"

    if $DRY_RUN; then
        log_dry "Would archive: $source → $archive_dir"
        return 0
    fi

    mkdir -p "$archive_dir"
    cp -r "$source"/* "$archive_dir"/ 2>/dev/null || true
    log_dbg "  Archived source to $archive_dir"
}

# ─────────────────────────────────────────────────────────────────────────────
# DELETE SOURCE DATA (with safety checks)
# FIX: Check only for NIfTI files produced from THIS specific conversion
#      (by bids_filename), not any run-numbered file anywhere in output_dir.
#      The old glob could match a previous subject's files and falsely confirm
#      success, allowing source deletion before conversion actually succeeded.
# ─────────────────────────────────────────────────────────────────────────────
safe_delete_source() {
    local source_dir="$1"
    local output_dir="$2"
    local bids_filename="$3"

    # Only delete if we have at least one NIfTI output for THIS conversion
    local nifti_exists=false
    if ls "${output_dir}/${bids_filename}"*.nii.gz &>/dev/null; then
        nifti_exists=true
    fi

    if ! $nifti_exists; then
        log_warn "  Skipping deletion — no NIfTI output found for: $bids_filename"
        return 1
    fi

    if $DRY_RUN; then
        log_dry "Would delete source: $source_dir"
        return 0
    fi

    local file_count
    file_count=$(find "$source_dir" -maxdepth 1 -type f | wc -l)

    if [ "$file_count" -eq 0 ]; then
        log_dbg "  Source already empty: $source_dir"
        return 0
    fi

    rm -rf "${source_dir:?}"/*
    log "  🗑️  Deleted source files in: $source_dir"
}

# ─────────────────────────────────────────────────────────────────────────────
# CREATE BIDS SCAFFOLD FILES
# FIX: Use $SCRIPT_NAME and $VERSION variables so scaffold content stays
#      accurate if the script is renamed or the version is bumped.
# ─────────────────────────────────────────────────────────────────────────────
create_bids_scaffold() {
    local bids_dir="$1"

    if $DRY_RUN; then
        log_dry "Would create BIDS scaffold in $bids_dir"
        return 0
    fi

    # ── dataset_description.json ──
    if [ ! -f "$bids_dir/dataset_description.json" ]; then
        cat > "$bids_dir/dataset_description.json" << DDJSON
{
    "Name": "My Study",
    "BIDSVersion": "1.9.0",
    "DatasetType": "raw",
    "License": "CC0",
    "Authors": [
        "FIXME: Add authors"
    ],
    "Acknowledgements": "",
    "HowToAcknowledge": "",
    "Funding": [],
    "EthicsApprovals": [],
    "ReferencesAndLinks": [],
    "DatasetDOI": "",
    "GeneratedBy": [
        {
            "Name": "${SCRIPT_NAME}",
            "Version": "${VERSION}",
            "Description": "Custom DICOM to BIDS conversion script"
        }
    ]
}
DDJSON
        log "Created dataset_description.json"
    fi

    # ── participants.tsv ──
    if [ ! -f "$bids_dir/participants.tsv" ]; then
        printf "participant_id\tage\tsex\tgroup\n" > "$bids_dir/participants.tsv"
        log "Created participants.tsv"
    fi

    # ── participants.json (data dictionary) ──
    if [ ! -f "$bids_dir/participants.json" ]; then
        cat > "$bids_dir/participants.json" << 'PJSON'
{
    "participant_id": {
        "Description": "Unique participant identifier"
    },
    "age": {
        "Description": "Age of participant in years",
        "Units": "years"
    },
    "sex": {
        "Description": "Biological sex of participant",
        "Levels": {
            "M": "male",
            "F": "female",
            "O": "other"
        }
    },
    "group": {
        "Description": "Experimental group",
        "Levels": {}
    }
}
PJSON
        log "Created participants.json"
    fi

    # ── README ──
    if [ ! -f "$bids_dir/README" ]; then
        cat > "$bids_dir/README" << README
# Dataset README

This dataset has been converted to BIDS format.

## Description
FIXME: Add study description here.

## Conversion
Converted using ${SCRIPT_NAME} v${VERSION}
See conversion logs in ${bids_dir}/logs/

## Notes
- Review all JSON sidecar files for correctness
- Update participants.tsv with actual demographics
- Add IntendedFor fields to all fieldmap JSON sidecars
- Run bids-validator to check compliance
README
        log "Created README"
    fi

    # ── CHANGES ──
    if [ ! -f "$bids_dir/CHANGES" ]; then
        cat > "$bids_dir/CHANGES" << 'CHANGES'
1.0.0 YYYY-MM-DD
  - Initial BIDS conversion
CHANGES
    fi

    # ── .bidsignore ──
    if [ ! -f "$bids_dir/.bidsignore" ]; then
        cat > "$bids_dir/.bidsignore" << 'IGNORE'
# Ignore conversion logs
logs/
# Ignore sourcedata
sourcedata/
IGNORE
        log "Created .bidsignore and CHANGES"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# DETECT SUBJECT / SESSION STRUCTURE
#
# Supports:
#   FLAT:        <input>/sub001/SAG/  <input>/sub002/SAG/
#   WITH_SES:    <input>/sub001/ses01/SAG/  <input>/sub001/ses02/SAG/
#   NAMED:       <input>/SUBJECT_001/SESSION_01/SAG/
# ─────────────────────────────────────────────────────────────────────────────
detect_structure() {
    local input="$1"
    local has_sessions=false

    for sub_dir in "$input"/*/; do
        [ ! -d "$sub_dir" ] && continue
        for child in "$sub_dir"/*/; do
            [ ! -d "$child" ] && continue
            local child_name
            child_name="$(basename "$child")"
            local child_upper="${child_name^^}"

            if [[ "$child_upper" =~ ^SES ]] || [[ "$child_upper" =~ SESSION ]] || \
               [[ "$child_upper" =~ ^VISIT ]] || [[ "$child_upper" =~ ^TP[0-9] ]] || \
               [[ "$child_upper" =~ ^TIMEPOINT ]]; then
                has_sessions=true
                break 2
            fi

            local grandchild_count=0
            local imaging_child=false
            for gc in "$child"/*/; do
                [ ! -d "$gc" ] && continue
                ((grandchild_count++)) || true
                local gc_name
                gc_name="$(basename "$gc")"
                if match_folder "$gc_name" 2>/dev/null; then
                    imaging_child=true
                fi
            done

            if $imaging_child && [ $grandchild_count -gt 0 ]; then
                has_sessions=true
                break 2
            fi
        done
    done

    if $has_sessions; then
        echo "sessions"
    else
        echo "flat"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# NORMALIZE SUBJECT ID → sub-XXX
# FIX: Removed the bare `id="${id#S}"` strip that incorrectly consumed the
#      first character of names like SCAN_01 → CAN_01. Now only strips
#      explicit known prefixes (sub-, SUB-, SUBJECT_) before falling back to
#      zero-padding purely numeric IDs.
# ─────────────────────────────────────────────────────────────────────────────
normalize_subject_id() {
    local raw="$1"
    local id="$raw"

    # Strip known prefixes — longest/most-specific first. Order matters:
    # each ${id#pattern} only strips once, against whatever id currently is,
    # so a short prefix tried before a longer one that contains it (e.g.
    # "SUB" before "SUBJECT_") will consume part of the longer prefix and
    # leave the rest stuck to the id (SUBJECT_001 -> SUB stripped -> JECT_001).
    id="${id#SUBJECT_}"
    id="${id#SUBJECT}"
    id="${id#subject_}"
    id="${id#subject}"
    id="${id#sub-}"
    id="${id#SUB-}"
    id="${id#sub}"
    id="${id#SUB}"

    # Remove leading underscores/hyphens
    id="${id#_}"
    id="${id#-}"

    # Zero-pad if purely numeric
    if [[ "$id" =~ ^[0-9]+$ ]]; then
        id=$(printf '%03d' "$((10#$id))")
    fi

    echo "sub-${id}"
}

# ─────────────────────────────────────────────────────────────────────────────
# NORMALIZE SESSION ID → ses-XXX
# ─────────────────────────────────────────────────────────────────────────────
normalize_session_id() {
    local raw="$1"
    local id="$raw"

    id="${id#SESSION_}"
    id="${id#SESSION}"
    id="${id#session_}"
    id="${id#session}"
    id="${id#ses-}"
    id="${id#SES-}"
    id="${id#ses}"
    id="${id#SES}"
    id="${id#VISIT}"
    id="${id#TIMEPOINT}"
    id="${id#TP}"

    id="${id#_}"
    id="${id#-}"

    if [[ "$id" =~ ^[0-9]+$ ]]; then
        id=$(printf '%02d' "$((10#$id))")
    fi

    echo "ses-${id}"
}

# ─────────────────────────────────────────────────────────────────────────────
# PROCESS A SINGLE SUBJECT (optionally with sessions)
# ─────────────────────────────────────────────────────────────────────────────
process_subject() {
    local sub_source_dir="$1"
    local sub_label="$2"
    local structure="$3"

    log "━━━ Processing ${sub_label} ━━━"

    if [ "$structure" = "sessions" ]; then
        for ses_dir in "$sub_source_dir"/*/; do
            [ ! -d "$ses_dir" ] && continue
            local ses_name
            ses_name="$(basename "$ses_dir")"
            local ses_label
            ses_label="$(normalize_session_id "$ses_name")"

            log "  Session: $ses_label (from $ses_name)"

            process_modality_folders "$ses_dir" "$sub_label" "$ses_label"
        done
    else
        process_modality_folders "$sub_source_dir" "$sub_label" ""
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# PROCESS ALL MODALITY FOLDERS WITHIN A DIRECTORY
# ─────────────────────────────────────────────────────────────────────────────
# Track runs per modality+suffix to auto-number duplicates
declare -A RUN_COUNTERS

process_modality_folders() {
    local parent_dir="$1"
    local sub_label="$2"
    local ses_label="$3"

    RUN_COUNTERS=()

    local unmatched=()

    shopt -s nullglob
    for modality_dir in "$parent_dir"/*/; do
        [ ! -d "$modality_dir" ] && continue

        local folder_name
        folder_name="$(basename "$modality_dir")"

        log_dbg "  Checking folder: $folder_name"

        if ! match_folder "$folder_name"; then
            unmatched+=("$folder_name")
            log_warn "  Unmatched folder (skipped): $folder_name"
            continue
        fi

        local modality="$MATCHED_MODALITY"
        local suffix="$MATCHED_SUFFIX"
        local task="$MATCHED_TASK"

        if ! has_source_files "$modality_dir"; then
            local found_sub=false
            for nested in "$modality_dir"/*/; do
                [ ! -d "$nested" ] && continue
                if has_source_files "$nested"; then
                    log_dbg "  Found nested data in: $(basename "$nested")"
                    modality_dir="$nested"
                    found_sub=true
                    break
                fi
            done

            if ! $found_sub; then
                log_warn "  No source files in: $folder_name"
                continue
            fi
        fi

        # ── Track run numbers using a safe delimiter (|) instead of underscore
        #    so task names containing underscores (e.g. "working_memory") don't
        #    cause the key to split incorrectly in fixup_run_numbers.
        local run_key="${modality}|${suffix}|${task}"
        if [ -n "${RUN_COUNTERS[$run_key]+x}" ]; then
            RUN_COUNTERS[$run_key]=$(( ${RUN_COUNTERS[$run_key]} + 1 ))
        else
            RUN_COUNTERS[$run_key]=1
        fi

        local bids_sub_dir="${OUTPUT_DIR}/${sub_label}"
        [ -n "$ses_label" ] && bids_sub_dir="${bids_sub_dir}/${ses_label}"
        bids_sub_dir="${bids_sub_dir}/${modality}"

        local bids_filename
        bids_filename="$(build_bids_filename "$sub_label" "$ses_label" "$modality" "$suffix" "$task" "" "$folder_name")"

        log "  📁 $folder_name → $modality/$bids_filename"

        if $COPY_SOURCEDATA; then
            archive_sourcedata "$modality_dir" "$sub_label" "$ses_label" "$folder_name"
        fi

        convert_folder "$modality_dir" "$bids_sub_dir" "$bids_filename" "$modality"

        local json_file="${bids_sub_dir}/${bids_filename}.json"
        enrich_json "$json_file" "$modality" "$task"

        if [ "$modality" = "fmap" ] && ! $DRY_RUN; then
            log_warn "  ⚠️  Fieldmap '$bids_filename': IntendedFor is empty — add target scans manually before running bids-validator."
        fi

        if $DELETE_SOURCE; then
            safe_delete_source "$modality_dir" "$bids_sub_dir" "$bids_filename"
        fi
    done
    shopt -u nullglob

    fixup_run_numbers "$sub_label" "$ses_label"

    if [ ${#unmatched[@]} -gt 0 ]; then
        log_warn "  Unmatched folders for ${sub_label}: ${unmatched[*]}"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# FIX RUN NUMBERS (rename files that need run- entity)
# FIX: Key now uses | as delimiter (set in process_modality_folders) so task
#      names with underscores split correctly.
# ─────────────────────────────────────────────────────────────────────────────
fixup_run_numbers() {
    local sub_label="$1"
    local ses_label="$2"

    for key in "${!RUN_COUNTERS[@]}"; do
        local count="${RUN_COUNTERS[$key]}"
        [ "$count" -le 1 ] && continue

        # Split on | instead of _
        IFS='|' read -r modality suffix task <<< "$key"

        local search_dir="${OUTPUT_DIR}/${sub_label}"
        [ -n "$ses_label" ] && search_dir="${search_dir}/${ses_label}"
        search_dir="${search_dir}/${modality}"

        [ ! -d "$search_dir" ] && continue

        local pattern="${sub_label}"
        [ -n "$ses_label" ] && pattern="${pattern}_${ses_label}"
        [ -n "$task" ] && [ "$modality" = "func" ] && pattern="${pattern}_task-${task}"
        pattern="${pattern}_${suffix}"

        local run_num=1
        for nii_file in "${search_dir}/${pattern}"*.nii.gz; do
            [ ! -f "$nii_file" ] && continue

            if $DRY_RUN; then
                log_dry "Would add run-$(printf '%02d' $run_num) to $(basename "$nii_file")"
            else
                local run_tag="run-$(printf '%02d' $run_num)"
                local new_pattern="${pattern%_${suffix}}_${run_tag}_${suffix}"

                for ext in .nii.gz .json .bval .bvec; do
                    local old="${search_dir}/${pattern}${ext}"
                    if [ -f "$old" ]; then
                        local new="${search_dir}/${new_pattern}${ext}"
                        mv "$old" "$new"
                        log_dbg "  Run fix: $(basename "$old") → $(basename "$new")"
                    fi
                done
            fi
            ((run_num++)) || true
        done
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# ADD PARTICIPANT TO TSV
# ─────────────────────────────────────────────────────────────────────────────
add_participant() {
    local sub_label="$1"
    local tsv_file="${OUTPUT_DIR}/participants.tsv"

    if $DRY_RUN; then
        log_dry "Would add $sub_label to participants.tsv"
        return 0
    fi

    if grep -q "^${sub_label}" "$tsv_file" 2>/dev/null; then
        log_dbg "  $sub_label already in participants.tsv"
        return 0
    fi

    printf "%s\tn/a\tn/a\tn/a\n" "$sub_label" >> "$tsv_file"
}

# ─────────────────────────────────────────────────────────────────────────────
# GENERATE MAPPING REPORT
# ─────────────────────────────────────────────────────────────────────────────
generate_report() {
    local report_file="${OUTPUT_DIR}/conversion_report_${TIMESTAMP}.txt"

    if $DRY_RUN; then
        log_dry "Would generate report at $report_file"
        return 0
    fi

    cat > "$report_file" << REPORT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  BIDS Conversion Report
  Generated: $(date)
  Script:  ${SCRIPT_NAME} v${VERSION}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Source Directory:  ${INPUT_DIR}
  Output Directory:  ${OUTPUT_DIR}
  Delete Source:     ${DELETE_SOURCE}
  Archive Source:    ${COPY_SOURCEDATA}

  Conversions:       ${CONVERTED}
  Warnings:          ${WARNINGS}
  Errors:            ${ERRORS}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Output Structure:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
$(find "$OUTPUT_DIR" -name "*.nii.gz" | sort | sed 's|'"$OUTPUT_DIR"'/||')

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Active Mapping Rules (${#MAPPING_PATTERNS[@]} total):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
$(for i in "${!MAPPING_PATTERNS[@]}"; do
    printf "  %-25s → %-6s / %-12s %s\n" \
        "${MAPPING_PATTERNS[$i]}" \
        "${MAPPING_MODALITIES[$i]}" \
        "${MAPPING_SUFFIXES[$i]}" \
        "${MAPPING_TASKS[$i]:+(task=${MAPPING_TASKS[$i]})}"
done)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
REPORT

    log "Report saved: $report_file"
}

# ─────────────────────────────────────────────────────────────────────────────
# GENERATE SAMPLE CONFIG FILE
# ─────────────────────────────────────────────────────────────────────────────
generate_sample_config() {
    local config_out="${OUTPUT_DIR}/sample_mapping.conf"

    if $DRY_RUN; then
        log_dry "Would generate sample config at $config_out"
        return 0
    fi

    cat > "$config_out" << 'SAMPLECONF'
###############################################################################
# BIDS Folder-to-Modality Mapping Configuration
#
# Format (tab or space separated):
#   <source_folder_pattern>   <bids_modality>   <bids_suffix>   [task_label]
#
# Patterns use bash globbing (case-insensitive).
# Lines starting with # are comments.
#
# Available modalities: anat, func, dwi, fmap, perf, pet, meg, eeg, ieeg, micr, motion
# See https://bids-specification.readthedocs.io/ for valid suffixes
###############################################################################

# ── Anatomical ──────────────────────────────────────────────────────────────
SAG*T1*             anat        T1w
*MPRAGE*            anat        T1w
*T1W*               anat        T1w
SAG                 anat        T1w
*T2W*               anat        T2w
*FLAIR*             anat        FLAIR

# ── Diffusion ───────────────────────────────────────────────────────────────
*DTI*               dwi         dwi
*DWI*               dwi         dwi

# ── Functional ──────────────────────────────────────────────────────────────
*REST*BOLD*         func        bold        rest
*BOLD*REST*         func        bold        rest
*NBACK*             func        bold        nback
*MOTOR*             func        bold        motor
*BOLD*              func        bold        unknown

# ── Fieldmaps ───────────────────────────────────────────────────────────────
*PHASE*DIFF*        fmap        phasediff
*MAGNITUDE*         fmap        magnitude

# ── Perfusion ───────────────────────────────────────────────────────────────
*ASL*               perf        asl

# ── PET ─────────────────────────────────────────────────────────────────────
*PET*               pet         pet

# ── MEG / EEG / iEEG ────────────────────────────────────────────────────────
*MEG*               meg         meg
*EEG*               eeg         eeg
*ECOG*              ieeg        ieeg
SAMPLECONF

    log "Sample config saved: $config_out"
    log "Edit this file and pass it with -c to customize folder mapping."
}

# ─────────────────────────────────────────────────────────────────────────────
# CONFIRMATION PROMPT FOR DESTRUCTIVE OPERATIONS
# ─────────────────────────────────────────────────────────────────────────────
confirm_delete() {
    if $DRY_RUN; then
        return 0
    fi

    echo ""
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}  WARNING: --delete-source is enabled!${NC}"
    echo -e "${RED}  Source DICOM files will be PERMANENTLY DELETED${NC}"
    echo -e "${RED}  after each successful conversion.${NC}"

    if $COPY_SOURCEDATA; then
        echo -e "${YELLOW}  (Originals WILL be archived in BIDS sourcedata/ first)${NC}"
    else
        echo -e "${RED}  Originals will NOT be archived. This is irreversible!${NC}"
    fi

    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    read -rp "Type 'DELETE' to confirm: " confirmation
    if [ "$confirmation" != "DELETE" ]; then
        log "Deletion cancelled by user."
        DELETE_SOURCE=false
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# PARALLEL SUBJECT PROCESSING
# Uses a simple semaphore pattern: cap active background jobs at $PARALLEL.
# ─────────────────────────────────────────────────────────────────────────────
wait_for_slot() {
    while [ "$(jobs -rp | wc -l)" -ge "$PARALLEL" ]; do
        sleep 0.2
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────
main() {
    parse_args "$@"

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  ${SCRIPT_NAME} v${VERSION}${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    log "Input:    $INPUT_DIR"
    log "Output:   $OUTPUT_DIR"
    log "Log:      $LOG_FILE"
    log "Parallel: $PARALLEL"
    $DRY_RUN && log "Mode:     DRY-RUN (no changes will be made)"
    echo ""

    check_dependencies

    if [ -n "$CONFIG_FILE" ]; then
        load_config_file "$CONFIG_FILE"
    else
        load_default_mapping
        log "Using default folder mapping (${#MAPPING_PATTERNS[@]} rules)"
    fi

    if $DELETE_SOURCE; then
        confirm_delete
    fi

    create_bids_scaffold "$OUTPUT_DIR"
    generate_sample_config

    local structure
    structure="$(detect_structure "$INPUT_DIR")"
    log "Detected structure: $structure"
    echo ""

    # ── Process each subject, with optional parallelism ──
    shopt -s nullglob
    local sub_count=0
    for sub_dir in "$INPUT_DIR"/*/; do
        [ ! -d "$sub_dir" ] && continue

        local raw_sub_name
        raw_sub_name="$(basename "$sub_dir")"

        local skip=false
        for skip_name in "BIDS" "sourcedata" "derivatives" "code" "stimuli" ".git"; do
            [ "$raw_sub_name" = "$skip_name" ] && skip=true
        done
        $skip && continue

        local sub_label
        sub_label="$(normalize_subject_id "$raw_sub_name")"

        add_participant "$sub_label"

        if [ "$PARALLEL" -gt 1 ]; then
            wait_for_slot
            process_subject "$sub_dir" "$sub_label" "$structure" &
        else
            process_subject "$sub_dir" "$sub_label" "$structure"
        fi

        ((sub_count++)) || true
        echo ""
    done
    shopt -u nullglob

    # Wait for any remaining background jobs
    wait

    generate_report

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  Conversion Complete${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  Subjects processed:  ${GREEN}${sub_count}${NC}"
    echo -e "  Successful converts: ${GREEN}${CONVERTED}${NC}"
    echo -e "  Warnings:            ${YELLOW}${WARNINGS}${NC}"
    echo -e "  Errors:              ${RED}${ERRORS}${NC}"
    echo ""
    echo -e "  Output: ${GREEN}${OUTPUT_DIR}${NC}"
    echo ""

    if [ $ERRORS -gt 0 ]; then
        echo -e "${RED}  ⚠ There were errors. Check the log: ${LOG_FILE}${NC}"
    fi

    echo -e "  ${BLUE}Validate with:${NC}  bids-validator ${OUTPUT_DIR}"
    echo ""

    echo -e "${YELLOW}  TODO:${NC}"
    echo "  1. Update participants.tsv with actual demographics"
    echo "  2. Update dataset_description.json with study details"
    echo "  3. Review task-unknown labels and rename appropriately"
    echo "  4. Add IntendedFor fields to all fieldmap JSON sidecars"
    echo "  5. Verify JSON sidecar acquisition parameters"
    echo ""

    return $ERRORS
}

# ─────────────────────────────────────────────────────────────────────────────
# ENTRYPOINT
# ─────────────────────────────────────────────────────────────────────────────
main "$@"
