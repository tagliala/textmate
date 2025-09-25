# Building TextMate Package via GitHub Actions

This repository includes a GitHub Actions workflow to build TextMate on macOS and create a distributable package.

## How to Trigger the Build

1. Navigate to the **Actions** tab in the GitHub repository
2. Select the **"Build TextMate Package"** workflow
3. Click **"Run workflow"**
4. Choose the build type (release or debug) - defaults to release
5. Click **"Run workflow"** button

## What the Workflow Does

The workflow performs the following steps:

1. **Environment Setup**:
   - Checks out the repository with submodules
   - Sets up Ruby 3.2
   - Installs required Homebrew dependencies:
     - boost (portable C++ libraries)
     - capnp (Cap'n Proto serialization)
     - google-sparsehash (cache-friendly hash map)
     - multimarkdown (marked-up plain text compiler)
     - ninja (build system)
     - ragel (state machine compiler)
     - gdbm (GNU Database Manager, needed for Ruby DBM gem)

2. **Ruby Dependencies**:
   - Installs the `dbm` gem required for credits generation
   - Verifies the gem can be loaded properly

3. **Build Process**:
   - Runs `./configure` to check dependencies and generate build files
   - Executes `ninja TextMate` to build the application
   - Handles build errors while ignoring warnings (as requested)

4. **Package Creation**:
   - Locates the built TextMate.app bundle
   - Copies it to a package directory
   - Creates a downloadable artifact

## Download the Package

After the workflow completes successfully:

1. Go to the workflow run page
2. Scroll down to the **Artifacts** section
3. Download the `textmate-package-<commit-sha>` artifact
4. Extract the ZIP file to get the TextMate.app bundle

## Build Configuration

- Default build type is **release** (optimized for distribution)
- Debug builds include additional debugging symbols and sanitizers
- The build target is `TextMate` which creates the full application bundle

## Requirements Met

This workflow addresses all the requirements from the issue:

- ✅ Manual trigger via `workflow_dispatch`
- ✅ macOS runner (`macOS-latest`)
- ✅ All Homebrew dependencies installed
- ✅ Ruby setup with `dbm` gem
- ✅ Package creation for distribution
- ✅ Build warnings ignored (errors still cause failure)
- ✅ Artifact upload for easy download

## Troubleshooting

If the build fails:

1. Check the workflow logs for specific error messages
2. Verify all dependencies are correctly installed
3. Check if there are any changes needed to the build configuration
4. The workflow will list build artifacts even on partial failures