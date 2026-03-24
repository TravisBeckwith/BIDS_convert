# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.1.0] - 2026-03-23

### Fixed
- **Critical:** Escaped `\$1`/`\$2` in all function bodies corrected to `$1`/`$2` — the
  previous code was passing the literal string `$1` as every function argument,
  silently breaking the entire conversion pipeline
- `safe_delete_source` no longer matches NIfTI files from *any* previous conversion
  in the output directory to confirm success — it now checks only for files matching
  the specific `$bids_filename` of the current operation, preventing source deletion
  after a failed conversion
- `normalize_subject_id` no longer strips a bare leading `S` from arbitrary folder
  names (e.g. `SCAN_01` was being mangled to `CAN_01`); only explicit known prefixes
  (`sub-`, `SUB-`, `SUBJECT_`, `SUBJECT`) are now removed
- `enrich_json` shell variables are now passed to Python via environment variables
  instead of direct interpolation into source, preventing syntax errors on folder
  names containing single quotes
- `fixup_run_numbers` run-counter key delimiter changed from `_` to `|` so task
  names containing underscores (e.g. `working_memory`) split correctly
- Removed dead `new_base` computation in `convert_folder` (two `sed` calls whose
  result was never used)

### Added
- Default mapping patterns for MEG, EEG, iEEG, microscopy (micr), and motion
  modalities — these were listed as supported in the header but had no mappings
- `build_bids_filename` now applies `task-` labels for MEG, EEG, and iEEG modalities
- `--parallel` flag is now functional — a `wait_for_slot` semaphore caps concurrent
  background jobs at the requested value (was parsed but completely ignored before)
- `--parallel` value is validated at startup; non-integer values exit with an error
- dcm2niix conversion logs are now preserved in `$OUTPUT_DIR/logs/` instead of being
  silently deleted after each successful run

### Changed
- `enrich_json` no longer injects an empty `"IntendedFor": []` placeholder into
  fieldmap sidecars — an empty list itself triggers a `bids-validator` error; a
  targeted `log_warn` is emitted instead and the post-conversion TODO list calls
  it out explicitly
- `dataset_description.json` and `README` scaffolds now use `$SCRIPT_NAME` and
  `$VERSION` variables rather than hardcoded strings
- Bumped version to `2.1.0`

## [2.0.0] - 2025-01-01

### Added
- Multi-modal support: anat, func, dwi, fmap, perf, PET
- Configurable folder-to-modality pattern matching
- Custom config file support (`-c` flag)
- Automatic session detection (flat vs. multi-session layouts)
- Run number auto-assignment for duplicate acquisitions
- Source archival to `sourcedata/` (`-s` flag)
- Safe source deletion with NIfTI verification (`-d` flag)
- Dry-run mode (`-n` flag)
- Parallel conversion support (`-p N` flag)
- JSON sidecar enrichment (TaskName, RepetitionTime, IntendedFor)
- Full BIDS scaffold generation
- Colored terminal output with log levels
- Conversion report generation
- Comprehensive built-in default mapping rules (~50 patterns)

### Changed
- Complete rewrite from v1.x single-modality approach

## [1.0.0] - 2024-01-01

### Added
- Initial release with basic DICOM to BIDS conversion
