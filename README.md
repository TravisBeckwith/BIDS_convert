# bids-convert [![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.20088220.svg)](https://doi.org/10.5281/zenodo.20088220)

A robust, multi-modal Bash script for converting DICOM datasets into [BIDS](https://bids-specification.readthedocs.io/) (Brain Imaging Data Structure) format using `dcm2niix`.

## Features

- **Multi-modal support** — anat, func, dwi, fmap, perf, pet, meg, eeg, ieeg, micr, motion
- **Automatic folder detection** — maps common DICOM folder naming conventions to BIDS modalities via configurable pattern matching
- **Session-aware** — automatically detects flat vs. multi-session directory structures
- **Run numbering** — auto-numbers duplicate acquisitions with BIDS `run-` entities
- **Source archival** — optionally copies originals into `sourcedata/` before converting
- **Safe deletion** — deletes source DICOMs only after verifying successful NIfTI output for that specific conversion
- **Dry-run mode** — preview every action without modifying anything
- **Parallel conversion** — run N subject conversions simultaneously with `-p N`
- **JSON enrichment** — automatically injects `TaskName` and `RepetitionTime` into sidecars; warns when `IntendedFor` needs to be set manually in fieldmap sidecars
- **Full BIDS scaffold** — generates `dataset_description.json`, `participants.tsv`, `README`, `CHANGES`, and `.bidsignore`
- **Conversion logs** — dcm2niix logs preserved in `logs/` for post-hoc QC

## Requirements

| Tool | Required | Notes |
|------|----------|-------|
| **dcm2niix** | ✅ | DICOM to NIfTI converter ([install](https://github.com/rordenlab/dcm2niix)) |
| **python3** | ✅ | Used for JSON sidecar enrichment |
| **jq** | Optional | Falls back to python3 if not installed |
| **bash** ≥ 4.0 | ✅ | Uses associative arrays and extended globbing |

### Install dependencies

```bash
# Ubuntu / Debian
sudo apt-get install dcm2niix python3 jq

# macOS (Homebrew)
brew install dcm2niix python3 jq

# Conda
conda install -c conda-forge dcm2niix
```

## Quick Start

```bash
# Clone the repository
git clone https://github.com/<your-username>/bids-convert.git
cd bids-convert

# Make the script executable
chmod +x bids_convert.sh

# Basic conversion
./bids_convert.sh -i /path/to/dicoms -o /path/to/BIDS

# Preview without making changes
./bids_convert.sh -i /path/to/dicoms -o /path/to/BIDS --dry-run --verbose
```

## Usage

```
./bids_convert.sh -i <source_dir> [OPTIONS]

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
  -h, --help              Show help
```

## Examples

```bash
# Convert with archival + source cleanup
./bids_convert.sh -i /data/raw -o /data/BIDS -s -d

# Use a custom mapping config
./bids_convert.sh -i /data/raw -o /data/BIDS -c my_mapping.conf

# Parallel conversion (4 subjects at a time)
./bids_convert.sh -i /data/raw -o /data/BIDS -p 4
```

## Expected Input Structure

The script supports two directory layouts, detected automatically:

### Flat (no sessions)

```
raw/
├── SUBJECT_001/
│   ├── SAG_T1/
│   ├── BOLD_REST/
│   └── DTI_64DIR/
└── SUBJECT_002/
    ├── SAG_T1/
    └── BOLD_REST/
```

### Multi-session

```
raw/
├── SUBJECT_001/
│   ├── SESSION_01/
│   │   ├── SAG_T1/
│   │   └── BOLD_REST/
│   └── SESSION_02/
│       ├── SAG_T1/
│       └── BOLD_REST/
```

## Custom Mapping Configuration

Generate a sample config, then edit it:

```bash
# Run once to generate sample_mapping.conf in the output directory
./bids_convert.sh -i /data/raw -o /data/BIDS

# Edit the generated file
vim /data/BIDS/sample_mapping.conf

# Re-run with custom mapping
./bids_convert.sh -i /data/raw -o /data/BIDS -c /data/BIDS/sample_mapping.conf
```

### Config file format

```
# <source_folder_pattern>  <bids_modality>  <bids_suffix>  [task_label]
SAG*T1*                    anat             T1w
*MPRAGE*                   anat             T1w
*DTI*                      dwi              dwi
*REST*BOLD*                func             bold           rest
*NBACK*                    func             bold           nback
*PHASE*DIFF*               fmap             phasediff
*ASL*                      perf             asl
*PET*                      pet              pet
*MEG*                      meg              meg
*EEG*                      eeg              eeg
```

Patterns use bash globbing and are matched case-insensitively. More specific patterns
should appear before general ones — the first match wins.

## Output

The script produces a BIDS-compliant directory:

```
BIDS/
├── dataset_description.json
├── participants.tsv
├── participants.json
├── README
├── CHANGES
├── .bidsignore
├── logs/                        ← dcm2niix conversion logs
├── sub-001/
│   ├── anat/
│   │   ├── sub-001_T1w.nii.gz
│   │   └── sub-001_T1w.json
│   ├── func/
│   │   ├── sub-001_task-rest_bold.nii.gz
│   │   └── sub-001_task-rest_bold.json
│   └── dwi/
│       ├── sub-001_dwi.nii.gz
│       ├── sub-001_dwi.json
│       ├── sub-001_dwi.bval
│       └── sub-001_dwi.bvec
```

## Post-Conversion Checklist

After conversion, you should:

1. **Validate** — run [`bids-validator`](https://bids-standard.github.io/bids-validator/) on the output directory
2. **Update metadata** — fill in `dataset_description.json` with your study details
3. **Add demographics** — update `participants.tsv` with age, sex, and group info
4. **Review task labels** — rename any `task-unknown` labels to their correct task names
5. **Set IntendedFor** — add `IntendedFor` paths in all fieldmap JSON sidecars (the script will warn you which files need this)
6. **Verify JSON sidecars** — confirm acquisition parameters are correct

```bash
# Install and run the BIDS validator
pip install bids-validator
bids-validator /path/to/BIDS
```

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

This project is licensed under the MIT License — see [LICENSE](LICENSE) for details.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for release history.
