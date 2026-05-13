# 🏗️ Architecture — Node Validator

> **Project:** Node Validator (`XML_checker.sh`)
> **Repository:** [github.com/enguru91/Node_Validator](https://github.com/enguru91/Node_Validator.git)
> **Author:** Eshan Gurusinghe · engurusinghe91@gmail.com
> **Current Version:** 1.3
> **Last Updated:** 2026-05

---

## Table of Contents

1. [Purpose & Problem Statement](#1-purpose--problem-statement)
2. [High-Level Architecture](#2-high-level-architecture)
3. [Module Breakdown](#3-module-breakdown)
4. [Data Flow](#4-data-flow)
5. [Key Design Decisions](#5-key-design-decisions)
6. [Internal Data Structures](#6-internal-data-structures)
7. [Input Specification](#7-input-specification)
8. [Output Specification](#8-output-specification)
9. [Error Handling Strategy](#9-error-handling-strategy)
10. [Platform & Tool Compatibility](#10-platform--tool-compatibility)
11. [Constraints & Known Limitations](#11-constraints--known-limitations)
12. [Version Architecture History](#12-version-architecture-history)
13. [Future Improvement Candidates](#13-future-improvement-candidates)

---

## 1. Purpose & Problem Statement

### The Problem

In telecom and enterprise system integration workflows, engineers frequently receive batches of XML configuration files — one per node — and must verify that specific parameters inside each file match the values in a reference parameter sheet (typically maintained in a spreadsheet or plain-text format).

Doing this manually is:
- Slow and error-prone at scale (tens or hundreds of XML files)
- Inconsistent across team members
- Hard to audit — no structured pass/fail record

### What This Tool Solves

Node Validator automates that verification. Given:
- A directory of XML files (or a single file), and
- A TAB-separated parameter reference file

...it maps each XML to its expected row, runs configurable XPath queries against each file, compares the extracted values to the expected values, and produces a structured pass/fail report.

The tool is deliberately **interactive, dynamic, and schema-agnostic** — it makes no assumptions about XML structure, field names, or how many parameters to check. Everything is configured at runtime through prompts.

---

## 2. High-Level Architecture

The program is structured as a **sequential pipeline** of five logical stages that run in a single Bash process. There are no subprocesses, background jobs, or external API calls.

```
╔══════════════════════════════════════════════════════════════════════╗
║                        XML_checker.sh                               ║
║                                                                      ║
║  ┌─────────────┐                                                     ║
║  │  STAGE 1    │  Environment Guard                                  ║
║  │             │  Bash version check · XML tool detection            ║
║  └──────┬──────┘                                                     ║
║         │                                                            ║
║  ┌──────▼──────┐                                                     ║
║  │  STAGE 2    │  User Input & Validation Layer                      ║
║  │             │  XML path · Parameter file · Labels · XPaths · Key  ║
║  └──────┬──────┘                                                     ║
║         │                                                            ║
║  ┌──────▼──────┐                                                     ║
║  │  STAGE 3    │  Mapping Engine                                     ║
║  │             │  Reads parameter .txt → builds key-indexed hash map ║
║  └──────┬──────┘                                                     ║
║         │                                                            ║
║  ┌──────▼──────┐                                                     ║
║  │  STAGE 4    │  XML Processing & Comparison Engine                 ║
║  │             │  Well-formedness check · XPath extraction · Diff    ║
║  └──────┬──────┘                                                     ║
║         │                                                            ║
║  ┌──────▼──────┐                                                     ║
║  │  STAGE 5    │  Report & Summary                                   ║
║  │             │  Pass/Fail counts · Unmatched XML · Unmatched keys  ║
║  └─────────────┘                                                     ║
╚══════════════════════════════════════════════════════════════════════╝
```

---

## 3. Module Breakdown

The script contains **four helper functions** and **five sequential execution stages**. All logic resides in a single file (`XML_checker.sh`).

### 3.1 Helper Functions

#### `trim()`
```
Purpose  : Remove leading and trailing whitespace from a string
Input    : A single string argument
Output   : The trimmed string via printf
Used by  : Parameter file parser · XML key extractor · Value comparator
```

Applied consistently before every comparison to prevent whitespace-induced false mismatches, especially important when processing files across different OS line-ending conventions (CRLF vs LF).

---

#### `validate_xml()`
```
Purpose  : Check whether an XML file is well-formed before processing
Input    : File path
Output   : Return code 0 (valid) or non-zero (invalid/malformed)
Depends  : xmlstarlet (preferred) or xmllint (fallback)
Behaviour: If neither tool is available, logs INFO and returns 0 (soft skip)
```

Acts as a **gate** — malformed XML files are immediately counted as failures and skipped before any XPath queries are attempted, preventing cryptic errors downstream.

---

#### `has_xml_tool()`
```
Purpose  : Detect whether at least one supported XML tool is installed
Input    : None
Output   : Return code 0 (tool found) or 1 (none found)
Used by  : Pre-flight check after user input collection
```

Called once as a hard requirement check after all user inputs are collected. If neither tool is present, the script exits immediately rather than running silently against all files and failing on every one.

---

#### `extract_value_xpath()`
```
Purpose  : Run an XPath expression against an XML file and return its string value
Input    : File path · XPath expression string
Output   : First matching node's text value (stdout) via head -n1
Depends  : xmlstarlet (preferred) or xmllint (fallback)
```

The core extraction primitive. Both tools are called in single-value mode — `head -n1` ensures that if an XPath matches multiple nodes, only the first is returned. This is an intentional design constraint (see Section 11).

XPath predicates such as `SubjectField[Type='FINGER_PRINT']/Value` are fully supported by both backend tools.

---

### 3.2 Execution Stages

#### Stage 1 — Environment Guard

Runs at startup before any user interaction.

- Checks `BASH_VERSINFO[0]` — exits immediately if Bash < 4 (associative arrays require Bash 4+)
- Sets `set -o pipefail` — ensures failures inside piped commands propagate correctly

---

#### Stage 2 — User Input & Validation Layer

Collects all runtime configuration interactively via `read` prompts. Validates each input before proceeding.

```
Inputs collected (in order):
  1. XML file location        → validated as existing directory or .xml file
  2. Parameter file path      → validated: exists · .txt extension · MIME type check
  3. Number of labels         → validated: positive integer
  4. For each label (1..N):
       - Friendly name        → defaults to "Label N" if blank
       - XPath expression     → required; cannot be empty
  5. Key column index         → validated: positive integer; default = 1
  6. Key XPath                → default = /Entities/Entity/EntityInfo/Name
```

XML files are discovered here using `find` (for directories) or accepted directly (for single files) and stored in the `XML_FILES` array, sorted alphabetically.

**MIME type validation** uses a two-stage approach to handle different environments:
```
Stage A: file --mime-type -b <path>   ← GNU/Linux standard flag
Stage B: file -b <path>               ← Fallback for WSL / macOS / BSD
Match pattern: text/* | *ASCII* | *UTF-8* | *Unicode*
If empty result: soft INFO warning, continues with .txt extension check
```

---

#### Stage 3 — Mapping Engine

Reads the parameter file line by line and builds an in-memory key-value hash map.

```
Input  : MAP_FILE (.txt, TAB-separated)
Process:
  - Skip blank lines
  - Skip comment lines (starting with #)
  - Split each line by TAB → column array
  - Validate column count matches NUM_LABELS
  - Trim all column values
  - Extract key from KEY_COL (1-based index)
  - Store: ROW_MAP[key] = "col1\tcol2\t..."
  - Track seen keys in ROW_SEEN to detect duplicates
  - Append key to PARAM_KEYS array (preserves insertion order)
Output : Populated ROW_MAP associative array
```

---

#### Stage 4 — XML Processing & Comparison Engine

Iterates over all discovered XML files. For each file:

```
1. validate_xml()          → skip if malformed, increment fail_files
2. extract_value_xpath()   → extract KEY value from XML using XML_KEY_XPATH
3. trim()                  → normalise extracted key
4. ROW_MAP lookup          → find expected row by key
5. For each label j:
     extract_value_xpath() → get actual value from XML
     trim()                → normalise
     Compare actual == expected
     Print OK or MISMATCH with expected/actual values
6. Set RESULT: ✅ or ❌ per file
```

---

#### Stage 5 — Report & Summary

After all XML files are processed:

- Prints total files, pass count, fail count
- **Unmatched XML files** — XML files where the key XPath returned empty or no matching parameter row was found
- **Unmatched parameter keys** — parameter rows in the `.txt` file that had no corresponding XML file

The unmatched parameter key detection requires a second pass over all XML files to rebuild `MATCHED_KEYS`, comparing against `PARAM_KEYS` to find the difference.

---

## 4. Data Flow

```
 Parameters.txt                    XML_Files/
 ┌──────────────────┐              ┌────────────────────┐
 │ key1  val1  val2 │              │ Node1.xml          │
 │ key2  val1  val2 │              │ Node2.xml          │
 │ key3  val1  val2 │              │ Node3.xml          │
 └────────┬─────────┘              └──────────┬─────────┘
          │ TAB-split                         │ find *.xml | sort
          ▼                                   ▼
 ┌─────────────────────┐          ┌────────────────────────┐
 │  ROW_MAP (hash map) │          │  XML_FILES[] (array)   │
 │  key1 → "v1\tv2"   │          │  [0] Node1.xml         │
 │  key2 → "v1\tv2"   │          │  [1] Node2.xml         │
 │  key3 → "v1\tv2"   │          │  [2] Node3.xml         │
 └──────────┬──────────┘          └──────────┬─────────────┘
            │                                │
            │         ┌──────────────────────┘
            │         │  For each XML file:
            │         ▼
            │   ┌─────────────────────────────────────┐
            │   │ 1. validate_xml()                   │
            │   │ 2. extract key via XML_KEY_XPATH     │
            │   │    → xml_key = "key1"               │
            │   └──────────────────┬──────────────────┘
            │                      │
            └──────────────────────┘
                       │ ROW_MAP[xml_key] lookup
                       ▼
            ┌─────────────────────────────────────────┐
            │  For each label XPath:                  │
            │    actual  = extract_value_xpath(file)  │
            │    expected = cols[j] from row          │
            │    actual == expected ? OK : MISMATCH   │
            └─────────────────────────────────────────┘
                       │
                       ▼
            ┌─────────────────────────────────────────┐
            │  stdout: per-file RESULT + Summary      │
            └─────────────────────────────────────────┘
```

---

## 5. Key Design Decisions

### 5.1 Keyed Mapping (not positional or filename-based)

XML files are matched to parameter rows by **value** — a unique key extracted from inside the XML using a user-configured XPath. The tool never assumes:
- that XML filenames correspond to parameter row order
- that files are processed in a predictable order

This makes the tool resilient to partial batches, renamed files, or files delivered out of order — common in real integration workflows.

### 5.2 Schema-Agnostic by Design

No XML element names, attributes, or document structure are hardcoded. Every field path is supplied at runtime. This allows the same tool to be reused across different XML schemas, projects, and teams without modification.

### 5.3 Graceful Tool Degradation

The tool supports two XML backends — `xmlstarlet` (preferred) and `xmllint` (fallback). The preference order is:
```
xmlstarlet → xmllint → soft skip with INFO (for well-formedness check only)
```
This avoids a hard dependency on a specific package and works across different Linux distributions and WSL environments.

### 5.4 Two-Stage MIME Detection (v1.3)

The `--mime-type` flag of the `file` command is not universally supported (absent on some BSD and older Linux builds). The fallback to `file -b` with pattern matching on plain-English output (`ASCII text`, `UTF-8 Unicode text`, etc.) ensures the parameter file type check works across GNU/Linux, WSL, and macOS without branching on OS type.

### 5.5 First-Match XPath Strategy

When an XPath matches multiple nodes, only the **first result** is used (`head -n1`). This is intentional — configuration files typically contain one authoritative value per field. Multi-value comparison is out of scope for this tool's purpose.

### 5.6 Single-File, No Dependencies

The entire tool is one script file with zero runtime dependencies beyond Bash 4+ and one XML tool. No config files, no companion scripts, no package managers. This is a deliberate choice for portability in locked-down enterprise environments where installing software is controlled.

---

## 6. Internal Data Structures

| Variable | Type | Purpose |
|---|---|---|
| `XML_FILES` | Indexed array | Sorted list of discovered `.xml` file paths |
| `ROW_MAP` | Associative array | Maps key string → TAB-joined expected value row |
| `ROW_SEEN` | Associative array | Tracks seen keys to detect duplicates in parameter file |
| `PARAM_KEYS` | Indexed array | Ordered list of all keys from the parameter file |
| `MATCHED_KEYS` | Associative array | Set of keys successfully matched to an XML file (built in Stage 5) |
| `LABEL_NAMES` | Indexed array | Friendly names for each label (parallel to LABEL_XPATHS) |
| `LABEL_XPATHS` | Indexed array | XPath strings for each label (parallel to LABEL_NAMES) |
| `UNMATCHED_XML` | Indexed array | XML files that could not be matched to a parameter row |
| `UNMATCHED_PARAM_KEYS` | Indexed array | Parameter keys with no corresponding XML file |
| `pass_files` | Integer | Count of fully-passed XML files |
| `fail_files` | Integer | Count of failed or skipped XML files |

---

## 7. Input Specification

### XML Input

| Property | Requirement |
|---|---|
| Format | Well-formed XML (`.xml` extension) |
| Source | Local directory or single file path |
| Discovery | `find <dir> -type f -name '*.xml' \| sort` |
| Encoding | UTF-8 recommended; tool inherits system locale |

### Parameter File

| Property | Requirement |
|---|---|
| Format | Plain text (`.txt` extension required) |
| Delimiter | TAB character (`\t`) between columns |
| Encoding | ASCII or UTF-8 |
| Comments | Lines starting with `#` are skipped |
| Blank lines | Skipped silently |
| Column count | Must exactly match `NUM_LABELS` on every data row |
| Key column | Any column (1-based index, user-defined) |
| Duplicate keys | Allowed with WARNING — last occurrence overwrites |

---

## 8. Output Specification

All output is written to **stdout**. Errors, warnings, and info notices are written to **stderr** (`>&2`).

### Per-file output tags

| Tag | Stream | Meaning |
|---|---|---|
| `OK:` | stdout | Label value matches expected |
| `MISMATCH:` | stdout | Label value differs from expected; shows both values |
| `RESULT: ✅` | stdout | All labels passed for this file |
| `RESULT: ❌` | stdout | One or more labels failed for this file |
| `FAIL:` | stdout | XML file is malformed; skipped entirely |
| `WARN:` | stdout | XML key not found, or no matching parameter row |
| `INFO:` | stderr | Non-critical notice (MIME fallback, missing XML tool) |
| `ERROR:` | stderr | Fatal input validation failure; script exits |

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Script completed (check RESULT lines for pass/fail detail) |
| `1` | Fatal error during input validation or environment check |

> Note: The script exits `0` even when some XML files fail comparison. Exit code only reflects whether the script itself ran successfully. Consumers who need a non-zero exit on any mismatch should post-process the output or extend the script with a final `exit $fail_files` statement.

---

## 9. Error Handling Strategy

The script uses a **fail-fast on configuration errors, soft-skip on data errors** approach.

```
Configuration errors  → immediate exit (exit 1)
  Examples: bad path · non-.txt file · wrong MIME · empty XPath
  Rationale: No point processing files if the setup is wrong

Data-level issues     → skip file, log, continue to next
  Examples: malformed XML · key not found in XML · no matching row
  Rationale: One bad file should not block validation of the rest

Missing tools (soft)  → INFO warning, skip well-formedness check only
  Example: neither xmlstarlet nor xmllint available at validate_xml()
  Note: has_xml_tool() is called separately as a hard check after input collection;
        this soft path is only reached if a tool disappears mid-run (edge case)
```

`set -o pipefail` is enabled to ensure pipeline failures (e.g. in `find | sort`) propagate as errors rather than being silently swallowed.

---

## 10. Platform & Tool Compatibility

| Environment | Supported | Notes |
|---|---|---|
| Ubuntu / Debian Linux | ✅ Full | Primary target platform |
| WSL (Windows Subsystem for Linux) | ✅ Full | Tested; MIME fallback handles `file` cmd difference |
| macOS | ⚠️ Partial | Requires Bash 4+ via Homebrew; BSD `file` handled by MIME fallback |
| Git Bash (Windows) | ❌ Not supported | `mapfile` and associative arrays unavailable |
| VirtualBox Linux VM | ✅ Full | Equivalent to native Linux |

| XML Tool | Priority | Notes |
|---|---|---|
| `xmlstarlet` | 1st (preferred) | More reliable predicate handling; explicit newline output |
| `xmllint` | 2nd (fallback) | Bundled with `libxml2-utils`; `--xpath` flag required |

---

## 11. Constraints & Known Limitations

**First-match only** — When an XPath matches multiple nodes, only the first result is used. Intentional for single-value configuration fields; unsuitable if multi-value comparison is needed.

**TAB-strict delimiter** — The parameter file must use TAB characters. Spaces between values will cause column count mismatches. No auto-detection of delimiter type.

**No header row support** — The parameter file has no concept of a header row. If a header exists, it will be treated as a data row and cause a key lookup failure.

**Synchronous, single-threaded** — Files are processed one at a time. For very large batches (hundreds of files), processing time scales linearly. Parallelism is not implemented.

**In-memory only** — All data structures live in the current shell process. No state is written to disk during execution. There is no resume or checkpoint capability.

**Duplicate key last-write-wins** — If the parameter file contains duplicate key values, the last row silently overwrites earlier ones (with a WARN). There is no strict duplicate rejection mode.

**Bash 4+ required** — Associative arrays (`declare -A`) are a Bash 4 feature. macOS ships with Bash 3.2 by default; users must install a newer version manually.

---

## 12. Version Architecture History

| Version | Architectural Change |
|---|---|
| **1.0** | Single-purpose script with hardcoded XPaths and expected values. No external input files. |
| **1.1** | Parameter values externalised into a `.txt` file. Script reads and parses the file at runtime. Introduced the parameter file parsing loop. |
| **1.2** | Full schema-agnostic design. XPaths, label names, key column, and key XPath all moved to runtime prompts. Introduced associative array mapping engine (`ROW_MAP`). Added well-formedness validation gate. |
| **1.3** | Added cross-platform MIME-type detection for the parameter file input. Two-stage `file` command fallback introduced to handle GNU/Linux vs. WSL/macOS differences. |

---

## 13. Future Improvement Candidates

These are not committed features — they are documented here as known improvement areas for contributors or future maintainers.

**Non-zero exit on any mismatch** — Add a final `exit $fail_files` so CI/CD pipelines can detect failures without parsing stdout.

**TSV/CSV auto-detection** — Detect the delimiter automatically (TAB vs. comma) rather than requiring strict TAB-only input.

**Header row support** — Allow the first row of the parameter file to be treated as column labels rather than data.

**HTML or JSON report output** — An optional `--output report.html` or `--output report.json` flag for structured, shareable results.

**Parallel processing** — Use `xargs -P` or background jobs with `wait` to process multiple XML files concurrently for large batches.

**Dry-run mode** — A `--dry-run` flag that validates all inputs and reports what would be checked, without actually running XPath queries.

**Config file mode** — Accept a YAML or INI config file as an alternative to interactive prompts, enabling non-interactive / scripted use.

---

## References

- [xmlstarlet documentation](http://xmlstar.sourceforge.net/doc/UG/xmlstarlet-ug.html)
- [xmllint man page](https://linux.die.net/man/1/xmllint)
- [XPath specification — W3C](https://www.w3.org/TR/xpath/)
- [Bash associative arrays — GNU manual](https://www.gnu.org/software/bash/manual/bash.html#Arrays)
- [WSL installation guide — Microsoft](https://learn.microsoft.com/en-us/windows/wsl/install)

---

*This document describes the architecture of Node Validator v1.3.
For usage instructions, see [README.md](../README.md).
For version history, see [CHANGELOG.md](../CHANGELOG.md).*
