# Gemini Guardrails

# This file contains guardrails for the Gemini AI assistant.
# These rules help the AI understand the project and how to best assist you.

# --- Project Scope ---
# The project is a single shell script, `update.sh`, for updating Linux systems.
# All modifications should be made to this file only.
rule "Scope" do
  # The AI should only modify the `update.sh` script.
  # Do not create new files or modify any other files.
  on_change "update.sh"
end

# --- Language ---
# The script is written in bash.
rule "Language" do
  # The AI should only write `bash` code.
  # Do not use any other programming languages.
  language "bash"
end

# --- Style ---
# The script has a defined style.
rule "Style" do
  # The AI should follow the existing style of the script.
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
  # Manual testing is required to ensure the script works as expected.
  no_tests
end

# --- Dependencies ---
# The script has some dependencies that are installed if missing.
rule "Dependencies" do
  # The AI should be careful when adding new dependencies.
  # If a new dependency is added, the AI should ensure it is installed if missing.
  # The installation should be done using the detected package manager.
  on "add_dependency" do
    # The AI should explain why the dependency is needed.
    # The AI should also add the code to install the dependency.
    # The installation should be done in a similar way to how `pv` and `lsof` are installed.
    warn "New dependency added. Please ensure it is installed if missing."
  end
end

# --- Idempotency ---
# The script should be idempotent.
rule "Idempotency" do
  # The AI should ensure that the script remains idempotent.
  # Running the script multiple times should not have unintended side effects.
  idempotent
end

# --- User Prompts ---
# The script should not have any new user prompts without explicit permission.
rule "User Prompts" do
  # The AI should not add any new user prompts without explicit permission.
  # The script should be as automated as possible.
  no_user_prompts
end

# --- Destructive Operations ---
# The script contains destructive operations like `rm`.
rule "Destructive Operations" do
  # The AI should be careful with destructive operations like `rm`.
  # The AI should explain why the destructive operation is necessary.
  on "destructive_operation" do
    warn "Destructive operation detected. Please review carefully."
  end
end
