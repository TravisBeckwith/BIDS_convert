# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
