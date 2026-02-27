<p align="center">
  <img src="https://img.shields.io/badge/version-2.0.0-blue.svg" alt="Version">
  <img src="https://img.shields.io/badge/BIDS-v1.9.0-yellow.svg" alt="BIDS">
  <img src="https://img.shields.io/badge/license-MIT-green.svg" alt="License">
  <img src="https://img.shields.io/badge/platform-linux%20%7C%20macOS%20%7C%20WSL-lightgrey.svg" alt="Platform">
  <img src="https://github.com/YOUR_USERNAME/bids-convert/actions/workflows/ci.yml/badge.svg" alt="CI">
</p>

# 🧠 bids-convert

**A comprehensive, multi-modal Bash script that converts raw DICOM neuroimaging
data into [BIDS](https://bids.neuroimaging.io/) format.**

Supports **anatomical, functional, diffusion, fieldmap, perfusion, and PET**
modalities with automatic folder detection, session handling, and optional
source cleanup.

---

## ✨ Features

| Feature | Description |
|---|---|
| 🔍 **Auto-detection** | Matches source folders to BIDS modalities via pattern rules |
| 📂 **Multi-modal** | anat, func, dwi, fmap, perf, pet |
| 🗂️ **Session support** | Auto-detects multi-session directory structures |
| ⚙️ **Configurable** | Custom mapping configs or use sensible defaults |
| 🏷️ **BIDS naming** | Generates compliant `sub-`, `ses-`, `task-`, `run-` entities |
| 📦 **Archival** | Optionally copies originals to `sourcedata/` |
| 🗑️ **Cleanup** | Safely deletes source DICOMs after verified conversion |
| 🔒 **Safety** | Dry-run mode, deletion confirmation, output validation |
| 📊 **Reporting** | Generates conversion reports and detailed logs |
| 🧩 **Scaffold** | Creates all required BIDS metadata files automatically |

---

## 📋 Requirements

| Tool | Version | Required |
|------|---------|----------|
| `bash` | ≥ 4.0 | ✅ |
| `dcm2niix` | ≥ 1.0.20211006 | ✅ |
| `python3` | ≥ 3.6 | ✅ |
| `jq` | ≥ 1.5 | Optional |
| `bids-validator` | latest | Optional |

### Quick Install

```bash
# Ubuntu / Debian
sudo apt-get install dcm2niix python3 jq

# macOS
brew install dcm2niix python3 jq

# Conda
conda install -c conda-forge dcm2niix jq

# BIDS Validator (optional)
npm install -g bids-validator
# or
pip install bids-validator