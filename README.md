# Node_Validator 🔍

![Bash](https://img.shields.io/badge/Shell-Bash%204%2B-4EAA25?logo=gnubash&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue)
![Version](https://img.shields.io/badge/Version-1.3-orange)

## Purpose

Use this tool to validate XML files against a node integration parameter file.

The tool **dynamically maps** given parameters against XML file parameters using a stable key and compares user-specified label XPaths. It supports XPath predicates for repeated nodes, enabling accurate cross-checking of XML configuration data at scale.

---

## Features

- Accepts a **directory of XML files** or a **single XML file** as input
- Maps parameter rows to XML files via a **configurable key column**
- Supports **XPath predicates** for repeated/conditional node matching (e.g. `SubjectField[Type='FINGER_PRINT']/Value`)
- Validates **XML well-formedness** before processing
- Detects **MIME type** of the parameter file to prevent format errors
- Reports **unmatched XML files** and **unmatched parameter keys** in the summary
- Works with either `xmlstarlet` or `xmllint` — at least one is required

---

## Pre-requirements ##

## 🚀 Quick Start

```bash
# Clone or download the script
git clone https://github.com/enguru91/Node_Validator
cd Node_Validator

### 1. Linux Environment

This tool requires a Linux environment. You can use **WSL** or **VirtualBox** on a local Windows PC.

To install WSL, follow the official Microsoft guide:
👉 https://learn.microsoft.com/ja-jp/windows/wsl/install

---

### 2. Required XML Packages

Install **at least one** of the following:

| Package | Purpose |
|---|---|
| `xmlstarlet` | XPath selection and XML validation (preferred) |
| `xmllint` (from `libxml2`) | Alternative for XPath extraction and validation |

#### Verify before installing

> **Note:** Commands may differ based on your Linux distribution.

```bash
$ xmlstarlet --version
1.6.1
compiled against libxml2 2.9.14, linked with 20914
compiled against libxslt 1.1.35, linked with 10139

$ xmllint --version
xmllint: using libxml version 20914
```

#### How to install

```bash
# Update package lists
$ sudo apt-get update

# Install xmlstarlet (recommended)
$ sudo apt-get install -y xmlstarlet

# OR install xmllint
$ sudo apt install libxml2-utils
```

---

### 3. Runtime Requirement — Bash 4+

The script uses **associative arrays**, which require Bash 4 or newer. Bash 3.x will not work.

```bash
$ bash --version
GNU bash, version 5.x.x(1)-release ...
```

---

## Execution Steps

### Step 1 — Check and Set Execution Permission

```bash
# Check current permissions
$ ls -ltr XML_checker.sh

# Add execution permission if missing
$ chmod u+x XML_checker.sh
# OR
$ chmod 755 XML_checker.sh
```

---

### Step 2 — Prepare Input Files

#### Parameters File (`.txt`)

Create a plain text file (e.g. `Parameters.txt`) containing the parameter values to cross-check against XML files. Each row corresponds to one XML file, and each column is **separated by a TAB character**.

```
<value1>	<value2>	<value3>	...
```

**Example:**

```
net10-cu-1	ORU_ABCNX000555
net10-cu-2	ORU_ABCNX000556
net10-cu-3	ORU_ABCNX000557
```

> The file can be saved in the same directory as the tool or at any relative path.

#### Target XML Files

Upload or place the XML files you want to validate (e.g. `Target_XML_file.xml`) in a directory or at a known path accessible to the tool.

---

## 📁 Suggested Project Structure

```
Node_Validator/
├── XML_checker.sh          # Main script
├── README.md               # This file
├── CHANGELOG.md            # Version history
├── examples/
│   ├── Parameters.txt   # Example TAB-separated parameter file
│   └── target_xmls/        # To be verified XML files
│       ├── ENTITY_001.xml
│       └── ENTITY_002.xml
└── docs/
    └── ARCHITECTURE.md     # Design notes (optional)

### Step 3 — Run the Tool

```bash
$ ./XML_checker.sh
```

The tool will prompt you interactively for the following inputs:

| Prompt | Description |
|---|---|
| **XML file location** | Path to a directory of `.xml` files or a single `.xml` file |
| **Parameter text file** | Path to the TAB-separated `.txt` parameters file |
| **Number of parameter points** | Must match the column count in the parameters file |
| **Label N friendly name** | A human-readable label for each parameter (e.g. `NodeName`) |
| **Label N XPath** | XPath to the target node in the XML (supports predicates) |
| **Key column index** | Column index (1-based) in the parameters file used to match each XML file |
| **Key XPath** | XPath to extract the matching key value from each XML file |

---

## Example Run

```
$ ./XML_checker.sh

Enter path to XML file location (directory with .xml files OR a single .xml file): XML_Files
Discovered 4 XML file(s).

Enter path to parameter text file (should be a .txt with TAB-separated): Parameters.txt

How many parameter points to check against the target XML file
(Number should be similar to parameter file's column count)? 2

Label 1 friendly name: NodeName
Label 1 XML Path (Ex XML predicates path: Entities/Entity/EntityInfo/Subject/SubjectField[Type='FINGER_PRINT']/Value):
  Entities/Entity/EntityInfo/Name

Label 2 friendly name: FingerPrint
Label 2 XML Path (Ex XML predicates path: Entities/Entity/EntityInfo/Subject/SubjectField[Type='FINGER_PRINT']/Value):
  Entities/Entity/EntityInfo/Subject/SubjectField[Type='FINGER_PRINT']/Value

Which parameter file's column index correspondence with the target XML KEY? (default 1) 1

XML Path to extract the KEY from XML (Ex:- /Entities/Entity/EntityInfo/Name):
  Entities/Entity/EntityInfo/Name
```

**Output:**

```
Checking file: XML_Files/SampleNodeParameter1.xml (key='net10-cu-1')
  OK: [NodeName] matches expected ('net10-cu-1')
  OK: [FingerPrint] matches expected ('ORU_ABCNX000555')
RESULT: XML_Files/SampleNodeParameter1.xml: ✅ All checks passed.

Checking file: XML_Files/SampleNodeParameter2.xml (key='net10-cu-2')
  OK: [NodeName] matches expected ('net10-cu-2')
  OK: [FingerPrint] matches expected ('ORU_ABCNX000556')
RESULT: XML_Files/SampleNodeParameter2.xml: ✅ All checks passed.

Checking file: XML_Files/SampleNodeParameter3.xml (key='net10-cu-3')
  OK: [NodeName] matches expected ('net10-cu-3')
  OK: [FingerPrint] matches expected ('ORU_ABCNX000557')
RESULT: XML_Files/SampleNodeParameter3.xml: ✅ All checks passed.

Checking file: XML_Files/SampleNodeParameter4.xml (key='net10-cu-4')
  OK: [NodeName] matches expected ('net10-cu-4')
  OK: [FingerPrint] matches expected ('ORU_ABCNX000558')
RESULT: XML_Files/SampleNodeParameter4.xml: ✅ All checks passed.

Summary:
  ⏭️ Total XML files considered: 4
  ✅ Passed: 4
  ❌ Failed: 0
```

---

## Output Reference

| Output Tag | Meaning |
|---|---|
| `OK:` | Parameter value matches the expected value from the parameters file |
| `MISMATCH:` | Value found in XML differs from the expected value |
| `RESULT: ✅ All checks passed.` | All labels matched for this XML file |
| `RESULT: ❌ One or more checks failed.` | At least one label mismatched for this XML file |
| `WARN:` | XML key not found, no matching parameter row, or duplicate key in parameters file |
| `FAIL:` | XML file is not well-formed and was skipped |
| `INFO:` | Non-critical notice (e.g. missing XML tool, MIME type fallback) |

---

## Version History

| Version | Changes |
|---|---|
| 1.0 | Initial release — hardcoded parameter checking |
| 1.1 | Parameters can be imported from a text file |
| 1.2 | Dynamic validation for any XML format; dynamic parameter mapping; XML well-formedness check |
| 1.3 | New environment text MIME-type validation added |

---

## 👤 Author

**Eshan Gurusinghe**
Ericsson
Customer Support & Integration Engineer | Yokohama, Japan

[![Email](https://img.shields.io/badge/Email-engurusinghe91@gmail.com-EA4335?style=flat-square&logo=gmail&logoColor=white)](mailto:engurusinghe91@gmail.com)
[![GitHub](https://img.shields.io/badge/GitHub-Profile-181717?style=flat-square&logo=github&logoColor=white)](https://github.com/enguru91)

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).