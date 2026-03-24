# Contributing to bids-convert

Thanks for your interest in contributing! This document provides guidelines for contributing to this project.

## How to Contribute

### Reporting Bugs

Open an issue using the **Bug Report** template and include:

- Your OS and Bash version (`bash --version`)
- `dcm2niix` version (`dcm2niix --version`)
- The command you ran
- Expected vs. actual behavior
- Relevant log output (from `logs/` in your BIDS output directory)

### Suggesting Features

Open an issue using the **Feature Request** template. Describe the use case and how the feature would help your BIDS conversion workflow.

### Submitting Changes

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-change`
3. Make your changes
4. Run the test suite: `bash tests/test_bids_convert.sh`
5. Commit with a clear message: `git commit -m "Add support for X modality"`
6. Push to your fork: `git push origin feature/my-change`
7. Open a Pull Request against `main`

## Development Guidelines

### Code Style

- Use `shellcheck` to lint all Bash code — the CI pipeline enforces this
- Use 4-space indentation
- Quote all variable expansions: `"$var"` not `$var`
- Use `[[ ]]` for conditionals over `[ ]`
- Add comments for non-obvious logic
- Follow existing naming conventions (lowercase for locals, UPPERCASE for globals)

### Adding New Modality Mappings

To add a new default mapping pattern, add an `add_mapping` call in the `load_default_mapping()` function:

```bash
add_mapping "*PATTERN*" "modality" "suffix" "task_or_empty"
```

Place more specific patterns before more general ones — the first match wins.

If the new modality requires a `task-` label in the BIDS filename, add a corresponding
`case` entry in `build_bids_filename()`.

### Testing

Run the test suite before submitting:

```bash
bash tests/test_bids_convert.sh
```

If adding new functionality, please add corresponding test cases.

## Code of Conduct

Be respectful and constructive. We're all here to make neuroimaging data easier to work with.
