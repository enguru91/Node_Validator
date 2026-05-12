# 🔍 XML File Validator

> **Keyed mapping + predicate-safe XPath validation for batch XML files**

[![Bash](https://img.shields.io/badge/Bash-4.0%2B-4EAA25?style=flat-square&logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![License](https://img.shields.io/badge/License-MIT-blue?style=flat-square)](LICENSE)
[![Version](https://img.shields.io/badge/Version-1.2-informational?style=flat-square)](CHANGELOG.md)
[![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20macOS-lightgrey?style=flat-square)](https://www.linux.org/)

---

## 📖 Overview

`XML_checker.sh` is an interactive Bash utility that validates XML configuration files against a set of expected parameter values defined in a TAB-separated text file. It maps each XML file to its corresponding parameter row via a configurable **key XPath**, then checks every specified field using **user-defined XPaths** — including XPaths with predicates for repeated/sibling nodes.

Designed for engineers who need to validate large batches of XML configuration files with consistency — without writing per-file scripts or manual inspection.

---

## ✨ Features

- ✅ **Batch validation** — point at a directory to process all `.xml` files at once, or validate a single file
- ✅ **Keyed row mapping** — each XML is matched to its expected values row via a configurable key XPath (no positional assumptions)
- ✅ **Predicate-safe XPaths** — supports complex XPaths like `/Entity/Info/Field[Type='NAME']/Value` for repeated sibling nodes
- ✅ **XML well-formedness check** — validates XML structure before running any comparisons
- ✅ **Flexible tool support** — works with either `xmlstarlet` or `xmllint` (auto-detected)
- ✅ **Dynamic label/XPath config** — configure any number of check points at runtime; no hardcoded fields
- ✅ **Unmatched reporting** — surfaces both XML files with no matching parameter row and parameter keys with no corresponding XML file
- ✅ **Clear pass/fail summary** — per-file results with expected vs. actual diff output for mismatches

---

## 📋 Requirements

| Requirement | Details |
|---|---|
| **Bash** | Version **4.0 or newer** (uses associative arrays) |
| **XML tool** | `xmlstarlet` *(preferred)* **or** `xmllint` — at least one must be installed |

### Install dependencies

```bash
# Debian / Ubuntu
sudo apt-get install xmlstarlet

# macOS (Homebrew)
brew install xmlstarlet

# RHEL / CentOS
sudo yum install xmlstarlet
```

> **Note:** `xmllint` is bundled with `libxml2-utils` and is often pre-installed.
> `xmlstarlet` is preferred — it handles edge cases more reliably for value extraction.

---

## 🚀 Quick Start

```bash
# 1. Clone or download the script
git clone https://github.com/YOUR_USERNAME/xml-file-validator.git
cd xml-file-validator

# 2. Make it executable
chmod +x XML_checker.sh

# 3. Run it
./XML_checker.sh
```

The script will interactively guide you through all required inputs.

---

## 🗂️ Input File Format

### Parameter File (`.txt`)

The parameter file must be **TAB-separated** (`.txt` extension required). Each row represents one XML file's expected values. One column must serve as the **key** — matched against a key XPath extracted from each XML.

```
# Comments (lines starting with #) and blank lines are ignored
<key_value>	<label_1_value>	<label_2_value>	...
```

**Example** — 3 columns, key in column 1:

```
ENTITY_001	Alice Johnson	active
ENTITY_002	Bob Smith	inactive
ENTITY_003	Carol White	active
```

> ⚠️ **Columns must be TAB-separated, not space-separated.**
> The number of columns must exactly match the number of labels you configure at runtime.

---

## 🖥️ Usage Walkthrough

When you run the script, it prompts for the following inputs in sequence:

```
Enter path to XML location (directory with .xml files OR a single .xml file):
> /path/to/xml/files/

Enter path to parameter text file (should be a .txt with TAB-separated):
> /path/to/params.txt

How many parameter points to check in the XML?
> 3

Label 1 friendly name: Entity Name
Label 1 XPath: /Entities/Entity/EntityInfo/Name

Label 2 friendly name: Status
Label 2 XPath: /Entities/Entity/EntityInfo/SubjectField[Type='STATUS']/Value

Label 3 friendly name: Category
Label 3 XPath: /Entities/Entity/EntityInfo/Category

Which column index (1-based) in the parameters file is the KEY to match XMLs? (default 1)
> 1

XPath to extract the KEY from XML (default /Entities/Entity/EntityInfo/Name):
> /Entities/Entity/EntityInfo/Name
```

---

## 📤 Output

### Per-file output

```
Checking file: /xml/files/ENTITY_001.xml (key='ENTITY_001')
  OK: [Entity Name] matches expected ('Alice Johnson')
  MISMATCH: [Status]
    Expected: 'active'
    Found:    'inactive'
  OK: [Category] matches expected ('COMMON')
RESULT: /xml/files/ENTITY_001.xml: ❌ One or more checks failed.

Checking file: /xml/files/ENTITY_002.xml (key='ENTITY_002')
  OK: [Entity Name] matches expected ('Bob Smith')
  OK: [Status] matches expected ('inactive')
  OK: [Category] matches expected ('STANDARD')
RESULT: /xml/files/ENTITY_002.xml: ✅ All checks passed.
```

### Summary

```
Summary:
  ⏭️  Total XML files considered: 3
  ✅ Passed: 2
  ❌ Failed: 1
  Unmatched XML files (no key or no row):
    - /xml/files/ENTITY_004.xml
  Unmatched parameter keys (no corresponding XML):
    - ENTITY_005
```

---

## ⚙️ How It Works

```
┌────────────────────────────────────────────────────────────┐
│                      XML_checker.sh                        │
│                                                            │
│  1. Discover XML files from path (directory or single)     │
│  2. Load parameter rows from .txt → keyed hash map         │
│  3. For each XML:                                          │
│     a. Validate well-formedness (xmlstarlet / xmllint)     │
│     b. Extract KEY value via key XPath                     │
│     c. Look up expected row in hash map by key             │
│     d. For each label: run XPath → compare to expected     │
│     e. Report OK / MISMATCH per label                      │
│  4. Report unmatched XMLs and unmatched parameter keys     │
│  5. Print final pass / fail summary                        │
└────────────────────────────────────────────────────────────┘
```

The key design decision is **keyed mapping** — XML files are never matched by filename or position, only by the value extracted from a user-specified XPath inside the file. This makes the tool resilient to file renaming, reordering, or partial batches.

---

## 📁 Suggested Project Structure

```
xml-file-validator/
├── XML_checker.sh          # Main script
├── README.md               # This file
├── CHANGELOG.md            # Version history
├── examples/
│   ├── sample_params.txt   # Example TAB-separated parameter file
│   └── sample_xmls/        # Example XML files
│       ├── ENTITY_001.xml
│       └── ENTITY_002.xml
└── docs/
    └── ARCHITECTURE.md     # Design notes (optional)
```

---

## 📝 Example Files

### `examples/sample_params.txt`

```
ENTITY_001	Alice Johnson	active	COMMON
ENTITY_002	Bob Smith	inactive	STANDARD
```

### `examples/sample_xmls/ENTITY_001.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Entities>
  <Entity>
    <EntityInfo>
      <Name>ENTITY_001</Name>
      <SubjectField>
        <Type>STATUS</Type>
        <Value>active</Value>
      </SubjectField>
      <SubjectField>
        <Type>COMMON_NAME</Type>
        <Value>Alice Johnson</Value>
      </SubjectField>
      <Category>COMMON</Category>
    </EntityInfo>
  </Entity>
</Entities>
```

---

## 🔄 Changelog

| Version | Description |
|---|---|
| `1.2` | Dynamic validation for any XML format; dynamic parameter mapping; XML well-formedness check |
| `1.1` | Parameter checking importable via external `.txt` file |
| `1.0` | Initial release with hardcoded parameter checking |

---

## ⚠️ Known Limitations

- Multi-value XPath results: only the **first matched node** is used for comparison (by design — `head -n1`)
- Parameter file must be strictly **TAB-separated** — mixed whitespace will cause column count mismatches
- Duplicate keys in the parameter file: the **last occurrence wins** (a warning is printed)
- Requires Bash 4+ — macOS ships with Bash 3.x by default; install via Homebrew: `brew install bash`

---

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Commit your changes: `git commit -m "feat: describe your change"`
4. Push and open a Pull Request

---

## 👤 Author

**Eshan Gurusinghe**
Ericsson
Customer Support & Integration Engineer | Yokohama, Japan

[![Email](https://img.shields.io/badge/Email-engurusinghe91@gmail.com-EA4335?style=flat-square&logo=gmail&logoColor=white)](mailto:engurusinghe91@gmail.com)
[![GitHub](https://img.shields.io/badge/GitHub-Profile-181717?style=flat-square&logo=github&logoColor=white)](https://github.com/YOUR_USERNAME)

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
