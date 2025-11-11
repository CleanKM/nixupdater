# Gemini Guardrails

# This file contains guardrails for the Gemini AI assistant.
# These rules help the AI understand the project and how to best assist you.

# --- Project Scope ---
# The project contains two scripts, one for Linux and one for macOS.
rule "Scope" do
  # The AI should identify which script to modify based on the user's request.
  # If the user's request is ambiguous, the AI should ask for clarification.
  on_change "linux/update.sh", "macos/update_macos.sh"
end

# --- Language ---
# Both scripts are written in bash.
rule "Language" do
  # The AI should only write `bash` code.
  # Do not use any other programming languages.
  language "bash"
end

# --- Style ---
# Both scripts have a defined style.
rule "Style" do
  # The AI should follow the existing style of the script being modified.
  # This includes:
  # - Using the defined color codes for output.
  # - Following the existing output format.
  # - Using `echo -e` for printing colored output.
  # - Maintaining the existing indentation and spacing.
  style_guide "Follow existing style"
end

# --- Testing ---
# There is no testing framework for this project.
rule "Testing" do
  # The AI should not add any tests.
  # Manual testing is required to ensure the scripts work as expected.
  no_tests
end
