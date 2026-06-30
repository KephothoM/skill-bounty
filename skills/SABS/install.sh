#!/bin/bash
# Installer for solana-advanced-builder-skill

KIT_SKILLS_DIR="${HOME}/.claude/skills"  # Adjust if using .agents or custom
SKILL_NAME="solana-advanced-builder"

if [ ! -d "$KIT_SKILLS_DIR" ]; then
  echo "Solana AI Kit skills directory not found at $KIT_SKILLS_DIR"
  echo "Please install the kit first."
  exit 1
fi

echo "Installing $SKILL_NAME..."
ln -sf "$(pwd)/skill" "$KIT_SKILLS_DIR/$SKILL_NAME"
cp -n agents/advanced-copilot.md "$KIT_SKILLS_DIR/$SKILL_NAME/" 2>/dev/null || true

echo "✅ Skill installed successfully! Load via SKILL.md router."
