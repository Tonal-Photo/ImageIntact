# ImageIntact Test Plans

This directory contains Xcode test plans for different testing scenarios. Test plans allow running specific subsets of tests with different configurations.

## Available Test Plans

### 1. Fast.xctestplan
**Purpose:** Quick smoke tests for rapid feedback during development

**Characteristics:**
- Execution time: < 1 minute
- Runs only critical path tests
- Parallel execution enabled
- No screenshots captured
- 60-second timeout per test

**When to use:**
- Pre-commit checks
- Quick validation after changes
- CI/CD pipeline for pull requests

**Selected tests (10 total):**
- Basic queue initialization and operations
- Round-robin distribution verification
- Essential UI validation (button states)
- Happy path backup flow

### 2. Comprehensive.xctestplan
**Purpose:** Full test suite execution for thorough validation

**Characteristics:**
- Execution time: 5-10 minutes
- Runs all unit and UI tests
- Screenshots on failure
- Main thread checker enabled
- 300-second timeout per test
- Code coverage enabled

**When to use:**
- Pre-release validation
- Nightly builds
- After major refactoring
- Branch merges to main

**Coverage:**
- All DestinationQueueTests (12 tests)
- All BackupCoordinatorTests (8 tests)
- All UI tests (37+ tests)

### 3. FullE2E.xctestplan
**Purpose:** End-to-end workflow validation with retry logic

**Characteristics:**
- Execution time: 15-30 minutes
- Sequential execution (no parallelization)
- Screenshots always captured
- Retry on failure (up to 3 attempts)
- Debug logging enabled
- 1800-second (30 min) timeout per test

**When to use:**
- Release candidates
- Major version updates
- After significant architectural changes
- Production deployment validation

**Selected workflows:**
- Complete backup flows (single and multiple destinations)
- Organization folder workflows
- Migration scenarios
- Preferences configuration
- Progress and verification tracking

## Running Test Plans

### From Xcode
1. Select the scheme in Xcode
2. Hold Option and click the Test button (or press Cmd+Shift+U)
3. Select the desired test plan from the dropdown
4. Click "Test"

### From Command Line

```bash
# Run Fast tests
xcodebuild test \
  -scheme ImageIntact \
  -testPlan Fast \
  -destination 'platform=macOS'

# Run Comprehensive tests
xcodebuild test \
  -scheme ImageIntact \
  -testPlan Comprehensive \
  -destination 'platform=macOS'

# Run E2E tests with results bundle
xcodebuild test \
  -scheme ImageIntact \
  -testPlan FullE2E \
  -destination 'platform=macOS' \
  -resultBundlePath TestResults.xcresult
```

### In CI/CD

```yaml
# Example GitHub Actions workflow
- name: Run Fast Tests
  run: |
    xcodebuild test \
      -scheme ImageIntact \
      -testPlan Fast \
      -destination 'platform=macOS' \
      -quiet

- name: Run Comprehensive Tests
  if: github.event_name == 'push' && github.ref == 'refs/heads/main'
  run: |
    xcodebuild test \
      -scheme ImageIntact \
      -testPlan Comprehensive \
      -destination 'platform=macOS' \
      -enableCodeCoverage YES
```

## Test Plan Configuration

### Environment Variables
Each test plan sets specific environment variables:

- `TEST_MODE`: Identifies which plan is running (FAST/COMPREHENSIVE/E2E)
- `FAST_TEST`: Set to "1" for fast tests
- `COMPREHENSIVE_TEST`: Set to "1" for comprehensive tests
- `E2E_TEST`: Set to "1" for E2E tests
- `LOG_LEVEL`: Controls logging verbosity (DEBUG for E2E)
- `ENABLE_DETAILED_LOGGING`: Set to "1" for verbose output
- `CAPTURE_SCREENSHOTS`: Set to "1" to capture UI screenshots

### Command Line Arguments
Test plans pass arguments to the app:

- `--uitest`: Enables UI test mode
- `--fast-test-mode`: Optimizes for speed
- `--comprehensive-test-mode`: Enables all checks
- `--e2e-test-mode`: Full workflow mode
- `--enable-all-features`: Unlocks all app features for testing

## Maintenance

### Adding Tests to Plans

1. **Fast Plan**: Only add tests that:
   - Execute in < 5 seconds
   - Test critical functionality
   - Have no external dependencies

2. **Comprehensive Plan**: Automatically includes all tests
   - No maintenance needed for new tests
   - They're automatically included

3. **E2E Plan**: Add tests that:
   - Validate complete user workflows
   - Test integration between components
   - Verify data persistence

### Updating Configurations

Test plan configurations can be modified for:
- Timeout values
- Parallelization settings
- Screenshot capture behavior
- Retry logic
- Environment variables
- Sanitizer settings

## Best Practices

1. **Keep Fast tests fast**: Remove tests that slow down the Fast plan
2. **Comprehensive should be comprehensive**: Don't skip tests without good reason
3. **E2E focuses on workflows**: Not individual components
4. **Update this README**: When modifying test plans
5. **Version control**: Test plans are JSON files and should be committed

## Troubleshooting

### Tests not appearing in plan
- Ensure test method names match exactly
- Check that test classes are included in the test target
- Verify test bundle identifier matches

### Plan not showing in Xcode
- Clean build folder (Shift+Cmd+K)
- Close and reopen Xcode
- Ensure .xctestplan files are added to project

### Different results between plans
- Check environment variables
- Verify timeout settings
- Review parallelization settings
- Check for test interdependencies