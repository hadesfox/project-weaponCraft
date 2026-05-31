---
name: skill-generator
description: |
  Generates high-quality Agent Skills following mgechev/skills-best-practices.
  Use when the user asks to create, build, generate, or scaffold a new skill
  (e.g., "create a pdf-editor skill", "build a skill for deploying to Docker",
  "make a skill that manages Git branches"). Also use when the user wants to
  validate or improve an existing skill against best-practices. Do NOT use for
  editing an existing skill's content -- use the skill they're already working on.
agent_created: true
---

# Skill Generator

Generate production-quality Agent Skills that follow the
[mgechev/skills-best-practices](https://github.com/mgechev/skills-best-practices)
specification. Every generated skill must pass the four-step validation:
Discovery, Logic, Edge Case, Architecture.

## Workflow

### 1. Gather Requirements

Ask the user in a single message:

- **What the skill should do** -- core functionality
- **Trigger phrases** -- what a user would say to activate it
- **Negative triggers** -- what it should NOT handle
- **Specific domain knowledge** -- APIs, schemas, company conventions

Do not interrogate. If the user has already stated intent, infer what you can
and confirm with a concise summary rather than re-asking.

### 2. Design the Structure

Based on requirements, determine which bundled resources are needed:

- **scripts/** -- when deterministic code would be rewritten repeatedly
- **references/** -- when domain knowledge (schemas, API docs, policies) is needed
- **assets/** -- when output templates or static files are needed

Settle on the skill name (lowercase, hyphens only, 1-64 chars).

### 3. Scaffold the Skill

Use the `scaffold.py` script (see Bundled Resources below) to create the
directory skeleton at `~/.workbuddy/skills/<skill-name>/`:

```
python scripts/scaffold.py <skill-name> [--path <parent-dir>]
```

If `--path` is omitted, defaults to `~/.workbuddy/skills/` (user scope).

### 4. Populate the Skill

#### 4a. Write SKILL.md

Edit the generated SKILL.md using the template (see Bundled Resources):

- **Frontmatter**: Fill in `name` (must match directory name) and `description`
  (include positive AND negative triggers, max 1024 chars)
- **Body**: Write instructions in imperative/infinitive form, using numbered
  steps for sequential workflows. Keep SKILL.md under 500 lines.
- Reference bundled resources with relative paths (e.g., `scripts/foo.py`).
  Indicate when a resource should be loaded (JiT).

Consult the `references/best-practices.md` content for detailed writing rules.

#### 4b. Create Bundled Resources

- **scripts/**: Write CLI-style scripts with clear docstrings.
- **references/**: Max one level deep. Name files descriptively.
- **assets/**: Templates, icons, schemas -- output material.

### 5. Validate

Use the `validate.py` script (see Bundled Resources) against the generated skill:

```
python scripts/validate.py <path/to/skill-folder>
```

### 6. Report

Present results to the user:
- List all generated files with paths
- Show validation results (pass/fail/warn)
- If validation fails, fix issues and re-validate
- Suggest next steps (test the skill, iterate)

## Discovery Validation

After generating, verify the skill triggers correctly:

1. State positive triggers and confirm they match user intent.
2. State negative triggers and confirm they won't cause false positives.
3. Ask the user to confirm before considering the skill complete.

## References

- The best-practices cheat sheet is embedded below (see Bundled Resources).
- The SKILL.md template is embedded below (see Bundled Resources).

---

# Bundled Resources

The sections below contain the full source of all bundled files.
When scaffolding a skill on a platform that supports file creation,
extract each code block into the file indicated by its heading.

---

## `references/best-practices.md`

```markdown
# Skills Best Practices -- Cheat Sheet

> Condensed from [mgechev/skills-best-practices](https://github.com/mgechev/skills-best-practices)

## File Structure

skill-name/
├── SKILL.md          ← Brain: metadata + core flow (<500 lines)
├── scripts/          ← Executable code (Python/Bash), deterministic tasks
├── references/       ← Domain docs (schemas, APIs), ONE LEVEL deep
└── assets/           ← Output templates, static files

**Never create:** README.md, CHANGELOG.md, LICENSE, CONTRIBUTING.md, .gitignore

## Frontmatter Rules

| Field | Rule |
|-------|------|
| `name` | Must match directory name exactly. 1-64 chars, lowercase + hyphens + digits only |
| `description` | Max 1024 chars. Include positive triggers AND negative triggers |
| `agent_created` | Must be `true` for agent-created skills |

### Description Quality

Good: "Creates React components with Tailwind CSS. Use when the user wants
   to build or update React UI. Don't use for Vue, Svelte, or vanilla CSS."

Bad: "React skills."
Bad: "Helps with React development."

The description must answer: **What does it do? When to use it? When NOT to use it?**

## Writing Instructions

1. **Imperative form** (verb-first), not second person
2. **Numbered steps** for sequential workflows
3. **Unified terminology** -- pick one term and stick to it

## Progressive Disclosure (JiT Loading)

Three-level loading:
1. **Metadata** (name + description) -- always in context (~100 words)
2. **SKILL.md body** -- loaded when skill triggers (<5k words)
3. **Bundled resources** -- loaded as-needed by Agent

## References Guidelines

- Max one directory level deep
- Name files descriptively: `schema.md`, `api_docs.md`
- If >10k words, include grep patterns in SKILL.md
- Reference files should NOT have YAML frontmatter

## Scripts Guidelines

- CLI-style: clear arguments, help text, exit codes
- Deterministic behavior
- Docstring at the top
- Use the runtime the user already has available

## Assets Guidelines

- Templates, icons, boilerplate code -- output material
- Not loaded into context; used by copying or referencing
- Name files descriptively

## Four-Step Validation

| Step | Goal | Method |
|------|------|--------|
| **Discovery** | Correct trigger/non-trigger | Test with positive and negative prompt examples |
| **Logic** | Deterministic, no ambiguity | Walk through each numbered step |
| **Edge Case** | Robust under unusual inputs | QA testing with empty/malformed inputs |
| **Architecture** | Progressive disclosure enforced | SKILL.md <500 lines, references flat, no forbidden files |
```

---

## `assets/SKILL.template.md`

```markdown
---
name: {{SKILL_NAME}}
description: >
  TODO: Describe what this skill does in 1-2 sentences. Then add trigger
  conditions: when to use it, and when NOT to use it. Include specific
  keywords the user might say to trigger this skill. Max 1024 chars.
agent_created: true
---

# {{SKILL_NAME}}

TODO: Brief overview of the skill's purpose (2-3 sentences).

## Workflow

TODO: Numbered steps describing the deterministic workflow.

1. First step -- describe the action in imperative form.
2. Second step -- what happens after step 1.
3. Third step -- continue the flow.

## References

TODO: List bundled resources and when to load them.

- `references/schema.md` -- database schema (load when querying data)
- `scripts/helper.py` -- utility script (run with `python scripts/helper.py`)

## Validation

TODO: Describe how to verify the skill works correctly.
```

---

## `scripts/scaffold.py`

```python
#!/usr/bin/env python3
"""Scaffold a new Agent Skill directory following best-practices.

Creates the directory skeleton with SKILL.md from the template
and empty scripts/, references/, assets/ subdirectories.
"""

import argparse
import io
import os
import sys
from pathlib import Path

# Force UTF-8 output on Windows
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")


TEMPLATE_DIR = Path(__file__).resolve().parent.parent / "assets"


def scaffold(skill_name: str, parent_path: str) -> Path:
    """Create the skill directory skeleton and return its path."""
    skill_dir = Path(parent_path) / skill_name

    if skill_dir.exists():
        print(f"Skill directory already exists: {skill_dir}")
        sys.exit(1)

    # Create directories
    skill_dir.mkdir(parents=True, exist_ok=False)
    (skill_dir / "scripts").mkdir(exist_ok=True)
    (skill_dir / "references").mkdir(exist_ok=True)
    (skill_dir / "assets").mkdir(exist_ok=True)

    # Copy SKILL.md template
    template_path = TEMPLATE_DIR / "SKILL.template.md"
    if template_path.exists():
        content = template_path.read_text(encoding="utf-8")
        content = content.replace("{{SKILL_NAME}}", skill_name)
        (skill_dir / "SKILL.md").write_text(content, encoding="utf-8")
    else:
        fallback = f"""---
name: {skill_name}
description: TODO: Describe what this skill does and when to use it. Include negative triggers.
agent_created: true
---

# {skill_name}

TODO: Write skill instructions here.
"""
        (skill_dir / "SKILL.md").write_text(fallback, encoding="utf-8")

    return skill_dir


def main():
    parser = argparse.ArgumentParser(
        description="Scaffold a new Agent Skill directory"
    )
    parser.add_argument(
        "name",
        help="Skill name (lowercase, hyphens only, 1-64 chars)",
    )
    parser.add_argument(
        "--path",
        default=None,
        help="Parent directory (default: ~/.workbuddy/skills/)",
    )

    args = parser.parse_args()

    # Validate skill name
    if not args.name.replace("-", "").replace("_", "").isalnum():
        print("Skill name must contain only lowercase letters, numbers, hyphens, underscores")
        sys.exit(1)
    if len(args.name) > 64:
        print("Skill name must be 64 characters or fewer")
        sys.exit(1)

    # Determine parent path
    if args.path:
        parent = Path(args.path).expanduser().resolve()
    else:
        parent = Path.home() / ".workbuddy" / "skills"

    parent.mkdir(parents=True, exist_ok=True)

    print(f"Initializing skill: {args.name}")
    print(f"   Location: {parent}")

    skill_dir = scaffold(args.name, str(parent))

    print(f"\nCreated skill directory: {skill_dir}")
    print(f"Created SKILL.md")
    print(f"Created scripts/")
    print(f"Created references/")
    print(f"Created assets/")
    print(f"\nSkill '{args.name}' initialized successfully.")
    print("\nNext steps:")
    print("1. Edit SKILL.md to complete the frontmatter and instructions")
    print("2. Add bundled resources in scripts/, references/, assets/ as needed")
    print("3. Validate with: python scripts/validate.py <skill-path>")


if __name__ == "__main__":
    main()
```

---

## `scripts/validate.py`

```python
#!/usr/bin/env python3
"""Validate an Agent Skill against mgechev/skills-best-practices.

Checks frontmatter, directory structure, line counts, and naming conventions.
"""

import argparse
import io
import re
import sys
from pathlib import Path

# Force UTF-8 output on Windows (GBK console can't encode emoji)
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")


FORBIDDEN_FILES = {"README.md", "CHANGELOG.md", "LICENSE", "CONTRIBUTING.md", ".gitignore"}
REQUIRED_DIRS = {"scripts", "references", "assets"}
MAX_SKILLMD_LINES = 500
MAX_DESCRIPTION_CHARS = 1024


def check_frontmatter(content: str, skill_name: str) -> list:
    """Validate YAML frontmatter."""
    errors = []

    if not content.startswith("---"):
        errors.append("Missing YAML frontmatter (file must start with ---)")
        return errors

    parts = content.split("---", 2)
    if len(parts) < 3:
        errors.append("Malformed frontmatter: missing closing ---")
        return errors

    fm = parts[1]

    name_match = re.search(r"^name:\s*(.+)$", fm, re.MULTILINE)
    desc_match = re.search(r"^description:\s*(.+)$", fm, re.MULTILINE | re.DOTALL)
    agent_match = re.search(r"^agent_created:\s*true", fm, re.MULTILINE)

    if not name_match:
        errors.append("Missing 'name' in frontmatter")
    else:
        fm_name = name_match.group(1).strip()
        if fm_name != skill_name:
            errors.append(f"Name '{fm_name}' does not match directory name '{skill_name}'")

    if not desc_match:
        errors.append("Missing 'description' in frontmatter")
    else:
        desc = desc_match.group(1).strip()
        if len(desc) < 50:
            errors.append(f"Description too short ({len(desc)} chars); should be detailed")
        if len(desc) > MAX_DESCRIPTION_CHARS:
            errors.append(f"Description exceeds {MAX_DESCRIPTION_CHARS} chars ({len(desc)})")
        has_negative = any(phrase in desc.lower() for phrase in [
            "do not use", "don't use", "not for", "not use", "not intended",
            "should not", "avoid", "skip"
        ])
        if not has_negative:
            errors.append("Description should include negative triggers")

    if not agent_match:
        errors.append("Missing 'agent_created: true' in frontmatter")

    return errors


def check_structure(skill_dir: Path) -> list:
    """Validate directory structure."""
    errors = []
    warnings = []

    skill_md = skill_dir / "SKILL.md"
    if not skill_md.exists():
        errors.append("Missing SKILL.md")
        return errors

    content = skill_md.read_text(encoding="utf-8")
    line_count = content.count("\n") + 1
    if line_count > MAX_SKILLMD_LINES:
        warnings.append(f"SKILL.md has {line_count} lines (recommended max: {MAX_SKILLMD_LINES})")

    for f in FORBIDDEN_FILES:
        if (skill_dir / f).exists():
            errors.append(f"Forbidden file: {f}")

    refs_dir = skill_dir / "references"
    if refs_dir.exists():
        for item in refs_dir.iterdir():
            if item.is_dir():
                errors.append(f"Nested directory in references/: {item.name}")
        for md_file in refs_dir.glob("*.md"):
            text = md_file.read_text(encoding="utf-8")
            if text.startswith("---"):
                warnings.append(f"{md_file.name} has frontmatter -- it looks like a SKILL.md")

    return errors + warnings


def check_instructions(content: str) -> list:
    """Check instruction writing style."""
    warnings = []

    body = content.split("---", 2)[-1].strip() if content.startswith("---") else content

    second_person = re.findall(r"\bYou should\b|\bYou must\b|\bYou can\b", body)
    if second_person:
        samples = second_person[:3]
        warnings.append(f"Use imperative form instead of second person. Found: {', '.join(samples)}")

    has_numbered_steps = bool(re.search(r"(?:^\d+\.\s|^\d+\)\s)", body, re.MULTILINE))
    if not has_numbered_steps and len(body) > 200:
        warnings.append("Consider using numbered steps for sequential workflows")

    return warnings


def validate(skill_path: str) -> dict:
    """Run all validation checks and return results."""
    skill_dir = Path(skill_path).resolve()

    if not skill_dir.is_dir():
        print(f"Not a directory: {skill_dir}")
        sys.exit(1)

    skill_name = skill_dir.name
    skill_md = skill_dir / "SKILL.md"

    results = {"errors": [], "warnings": []}

    if not skill_md.exists():
        results["errors"].append("Missing SKILL.md -- not a valid skill")
        return results

    content = skill_md.read_text(encoding="utf-8")

    results["errors"].extend(check_frontmatter(content, skill_name))
    results["warnings"].extend(check_instructions(content))

    struct_issues = check_structure(skill_dir)
    for issue in struct_issues:
        if issue.startswith("Forbidden") or issue.startswith("Missing"):
            results["errors"].append(issue)
        else:
            results["warnings"].append(issue)

    return results


def main():
    parser = argparse.ArgumentParser(
        description="Validate an Agent Skill against best-practices"
    )
    parser.add_argument(
        "skill_path",
        help="Path to the skill directory to validate",
    )

    args = parser.parse_args()

    print(f"Validating skill at: {args.skill_path}\n")

    results = validate(args.skill_path)

    has_errors = len(results["errors"]) > 0
    has_warnings = len(results["warnings"]) > 0

    if results["errors"]:
        print(f"Errors ({len(results['errors'])}):")
        for e in results["errors"]:
            print(f"   - {e}")
        print()

    if results["warnings"]:
        print(f"Warnings ({len(results['warnings'])}):")
        for w in results["warnings"]:
            print(f"   - {w}")
        print()

    if not has_errors and not has_warnings:
        print("All checks passed!")
    elif not has_errors:
        print("Validation passed with warnings (see above).")
    else:
        print(f"Validation failed with {len(results['errors'])} error(s).")

    sys.exit(1 if has_errors else 0)


if __name__ == "__main__":
    main()
```
