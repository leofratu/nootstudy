"""Publish only explicitly reviewed artifacts to the two existing PR branches.

This is a publication step, not a test pass: existing native timing failures are
validated against an explicit list, printed and recorded without changing tests.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--curriculum', type=Path, required=True)
parser.add_argument('--design', type=Path, required=True)
parser.add_argument('--before', type=Path, required=True)
parser.add_argument('--design-patch-sha', required=True)
parser.add_argument('--design-run', required=True)
args = parser.parse_args()
FIX = 'fix/biology-curriculum-and-reliability'
DESIGN = 'design/biology-study-experience'
OLD_FIX = '4bf9d72d0063ab06b7502d36f664105227f1ce0b'
OLD_DESIGN = 'c2aed9303338d716f27644c5696affb63bfa0b7e'
BASE_RUN = '36007838225'
URL = 'https://github.com/leofratu/nootstudy'

def run(*command):
    return subprocess.check_output(command, text=True).strip()

def git(*command):
    return run('git', *command)

def one(root, name):
    matches = list(root.rglob(name))
    if len(matches) != 1:
        raise RuntimeError(f'Expected exactly one {name} in {root}, found {len(matches)}')
    return matches[0]

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def unpack(root):
    destination = Path(tempfile.mkdtemp(prefix='reviewed-source-'))
    with tarfile.open(one(root, 'final-source.tar')) as archive:
        archive.extractall(destination, filter='data')
    return destination

for branch, expected in [(FIX, OLD_FIX), (DESIGN, OLD_DESIGN)]:
    actual = git('ls-remote', 'origin', f'refs/heads/{branch}').split()[0]
    if actual != expected:
        raise RuntimeError(f'{branch} moved after review; refusing to overwrite it')
assert git('rev-parse', 'HEAD') == OLD_FIX
assert not git('status', '--porcelain')
git('config', 'user.name', 'Leo Fratu')
git('config', 'user.email', '181772404+leofratu@users.noreply.github.com')

allowed_failures = {
    'PerformanceBenchmarks/benchmarkReviewQueue()',
    'PerformanceBenchmarks/benchmarkEvidenceScoring()',
    'ReviewQueueBulkTests/refresh2000CardsPerformance()',
}
summaries = {}
for label, root in [('curriculum', args.curriculum), ('design', args.design)]:
    summary = json.loads(one(root, 'functional-summary.json').read_text())
    assert summary['totalTestCount'] == 384 and summary['skippedTests'] == 1
    failures = summary.get('testFailures', [])
    assert len(failures) == summary['failedTests']
    assert {f['testIdentifierString'] for f in failures} <= allowed_failures
    assert summary['passedTests'] + summary['failedTests'] + 1 == 384
    print(label, json.dumps(summary, indent=2))
    summaries[label] = summary
visual = json.loads(one(args.design, 'visual-summary.json').read_text())
assert visual['totalTestCount'] == 2 and visual['passedTests'] == 2
assert visual['failedTests'] == 0 and visual['skippedTests'] == 0
patch = one(args.curriculum, 'final.patch')
assert digest(patch) == '34641d89ad8e45d623d2fad26f216ed1ce9249900f142da54f226266b9dd3d0a'
assert digest(one(args.design, 'final.patch')) == args.design_patch_sha
curriculum = unpack(args.curriculum)
design = unpack(args.design)
for name, expected in {
    'BiologyContinuationTests.swift': '95b454acb563e90dcbef29de7950c383a6bff85170ed2be761c47b3dd11addab',
    'BiologyMasteryMappingTests.swift': '4572d87c2f55763efeef08c044fff63975c938240fa6054a441c33849907afe0',
}.items():
    assert digest(curriculum / 'IBVaultTests' / name) == expected
    assert digest(design / 'IBVaultTests' / name) == expected


def verify_source(expected):
    roots = ('IBVault/', 'IBVaultTests/', 'IBVaultVisualTests/', 'IBVault.xcodeproj/', 'scripts/')
    names = set(git('ls-files').splitlines())
    names.update(str(p.relative_to(expected)) for p in expected.rglob('*.swift'))
    checked = 0
    for name in sorted(names):
        if name == 'project.yml' or name.startswith(roots):
            path = Path(name)
            if not (expected / name).exists():
                raise RuntimeError(f'Unexpected application file {name}')
            if not path.exists() or path.read_bytes() != (expected / name).read_bytes():
                raise RuntimeError(f'Application source differs from tested artifact: {name}')
            checked += 1
    print(f'Byte-for-byte verified {checked} application, test, project and audit files')


def validation_text(label, run_id, source_commit):
    summary = summaries[label]
    lines = [f'# Biology {label} continuation validation', '',
             'Validation date: 24 September 2026.', '',
             f'Native evidence: {URL}/actions/runs/{run_id}', '',
             f'Implementation commit before documentation: `{source_commit}`.', '',
             'The committed application, tests, Xcode project and audit script were compared byte-for-byte with the native-tested source artifact. Documentation and CI wiring are reported separately. The full test suite was run without excluding performance tests.', '',
             '| Suite | Total | Passed | Failed | Skipped |',
             '| --- | ---: | ---: | ---: | ---: |',
             f"| Native functional and performance suite | {summary['totalTestCount']} | {summary['passedTests']} | {summary['failedTests']} | {summary['skippedTests']} |"]
    if label == 'design':
        lines.append('| Native visual suite | 2 | 2 | 0 | 0 |')
    lines += ['', '**All functional regressions passed, including the 13 continuation tests. The full native suite is not green.** The skipped test is the existing opt-in screenshot fixture, not a newly disabled regression. Failures recorded in this run:', '']
    for failure in summary.get('testFailures', []):
        lines += [f"- `{failure['testIdentifierString']}`: {failure['failureText']}"]
    lines += ['', 'These timing assertions also failed on unchanged main in the earlier baseline run. Their limits remain unchanged; no test was disabled, relaxed or marked as an expected failure. Runner variability and different execution order mean the measurements are not a controlled speedup claim.', '',
              f'Unchanged-main comparison: {URL}/actions/runs/35994816730',
              f'Isolated queue comparison, including unsuccessful experiments: {URL}/actions/runs/36005443286', '',
              'The retained optimization avoids unnecessary fuzzy-signature construction and repeated scope normalization. Projected/registered-model fetch experiments were not included. Cold/warm reads, pending changes, cross-context membership, review history, SL/HL gates and mastery aliases have regression coverage.', '',
              'The curriculum audit passes with 40 topic packages, 126 lesson sections, 194 questions and 123 explicit understanding references. All topic packages remain partial. Diagram coverage, some content areas, the practical programme and independent teacher review remain incomplete. Native renders do not certify VoiceOver or a complete manual keyboard/student journey.', '']
    return '\n'.join(lines)

# PR 1: use the exact reviewed patch, not a freshly generated approximation.
git('apply', '--check', str(patch))
git('apply', str(patch))
for name in ['BiologyContinuationTests.swift', 'BiologyMasteryMappingTests.swift']:
    shutil.copyfile(curriculum / 'IBVaultTests' / name, Path('IBVaultTests') / name)
verify_source(curriculum)
# Full history makes the baseline portion reproducible as well as resource counts.
run('python3', 'scripts/audit_biology.py', '--output', 'docs/biology-coverage.json')
git('diff', '--check')
git('add', 'IBVault/Materials/Biology/C.json', 'scripts/audit_biology.py', 'docs/biology-coverage.json')
git('commit', '-m', 'content: expand respiration and photosynthesis with level-gated practice')
git('add', 'IBVault/Models/CurriculumNode.swift', 'IBVault/Services/BiologyCatalog.swift',
    'IBVault/Services/BiologyStudyService.swift', 'IBVault/Services/CardDuplicatePolicy.swift',
    'IBVaultTests/BiologyContinuationTests.swift', 'IBVaultTests/BiologyMasteryMappingTests.swift',
    'IBVault.xcodeproj/project.pbxproj')
git('commit', '-m', 'fix: preserve canonical mastery and streamline duplicate matching with regressions')
implementation = git('rev-parse', 'HEAD')
Path('docs/biology-continuation-validation.md').write_text(validation_text('curriculum', BASE_RUN, implementation))
p = Path('docs/biology-audit.md')
s = p.read_text().replace('The continuation evidence below identifies later tested changes.',
                         'Completed continuation results are in `biology-continuation-validation.md`.')
s = s.replace('All numerical practice datasets are explicitly synthetic; these are original questions, not past-paper reproductions.',
              'The new numerical examples are synthetic practice material; these are original questions, not past-paper reproductions.')
p.write_text(s)
git('add', 'docs/biology-audit.md', 'docs/biology-continuation-validation.md')
git('commit', '-m', 'docs: record completed continuation validation and remaining coverage gaps')
fix_sha = git('rev-parse', 'HEAD')
assert not git('status', '--porcelain')

# PR 2: merge PR 1 locally without rewriting either existing branch's history.
git('checkout', '--detach', OLD_DESIGN)
git('merge', '--no-ff', '--no-edit', fix_sha)
for name in ['IBVault/Views/Subjects/BiologyStudyView.swift', 'IBVaultVisualTests/BiologyVisualTests.swift']:
    shutil.copyfile(design / name, Path(name))
verify_source(design)
git('diff', '--check')
git('add', 'IBVault/Views/Subjects/BiologyStudyView.swift', 'IBVaultVisualTests/BiologyVisualTests.swift')
git('commit', '-m', 'fix: pin syllabus filters and remove blank sidebar rows in native study layouts')
design_implementation = git('rev-parse', 'HEAD')

# Keep visual checks active on future changes, in their own native process.
p = Path('.github/workflows/study-validation.yml')
s = p.read_text().replace("      - 'IBVaultTests/**'", "      - 'IBVaultTests/**'\n      - 'IBVaultVisualTests/**'\n      - 'IBVault.xcodeproj/**'")
assert 'native-visual-tests:' not in s
s += '''
  native-visual-tests:
    runs-on: macos-26
    timeout-minutes: 20
    steps:
      - uses: actions/checkout@v4
        with:
          persist-credentials: false
      - name: Select Xcode and generate the native visual scheme
        run: |
          set -euo pipefail
          sudo xcode-select -s /Applications/Xcode_26.4.app/Contents/Developer
          brew install xcodegen
          xcodegen generate
      - name: Render and test every native Biology fixture
        run: |
          set -euo pipefail
          xcodebuild test -project IBVault.xcodeproj -scheme IBVaultVisual -destination 'platform=macOS' \\
            -derivedDataPath "$RUNNER_TEMP/visual-build" -resultBundlePath "$RUNNER_TEMP/visual-tests.xcresult" \\
            -jobs 2 -parallel-testing-enabled NO \\
            CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \\
            2>&1 | tee "$RUNNER_TEMP/visual-tests.log"
      - name: Retain visual evidence
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: native-visual-evidence-${{ github.sha }}
          path: |
            ${{ runner.temp }}/visual-tests.log
            ${{ runner.temp }}/visual-tests.xcresult
            /tmp/nootstudy-snapshots
          retention-days: 7
'''
p.write_text(s)
run('ruby', '-ryaml', '-e', 'YAML.load_file(ARGV[0])', str(p))
git('add', str(p))
git('commit', '-m', 'ci: run the isolated native visual suite on study changes')

shots = Path('docs/screenshots/biology')
shots.mkdir(parents=True, exist_ok=True)
selected = ['after-learn-1280-light.png', 'after-learn-420-light.png', 'after-learn-420-dark.png',
            'after-quiz-feedback-dark.png', 'after-respiration-hl-1280.png']
for name in selected:
    shutil.copyfile(one(args.design, name), shots / name)
shutil.copyfile(one(args.before, 'before-learn-1280.png'), shots / 'before-learn-1280.png')
text = validation_text('design', args.design_run, design_implementation)
text += f'''## Screenshots and scope

Before is the functional workspace from PR #15 at `33f4874c10fcf3144cb15046d94e217a2e6b969f`, not unchanged main. Source: {URL}/actions/runs/35995407219. After images are actual SwiftUI/AppKit renders of the verified design artifact using an in-memory synthetic student fixture. No learner records or screen-capture permission changes are included.

The two visual tests render 13 fixtures: light/dark lessons at 420, 768 and 1,280 points, flashcards, practice, HL water potential, light/dark quiz feedback, SL photosynthesis and HL respiration. These are macOS window sizes, not mobile-browser or iOS-device tests. Pinned filters remain visible while the topic list scrolls; the bounded 40-topic list no longer uses lazy rows that produced blank areas during programmatic navigation.

| Before: PR #15 workspace | After: redesign |
| --- | --- |
| ![Before](screenshots/biology/before-learn-1280.png) | ![After](screenshots/biology/after-learn-1280-light.png) |

| Narrow light window | Narrow dark window |
| --- | --- |
| ![Narrow light](screenshots/biology/after-learn-420-light.png) | ![Narrow dark](screenshots/biology/after-learn-420-dark.png) |

![Readable checked answers](screenshots/biology/after-quiz-feedback-dark.png)

![Expanded HL respiration](screenshots/biology/after-respiration-hl-1280.png)

The ongoing study workflow now includes a separate `native-visual-tests` job and watches visual-test/project changes. This CI-wiring addition does not change the tested application or assertions. The redesign scope is Biology study/navigation, not every dashboard, grade-management or AI-chat screen. PR #16 remains stacked on #15; merge order is #15 then #16, with retargeting after the base merges. Neither PR has been merged by this publication step.
'''
Path('docs/biology-design-validation.md').write_text(text)
git('add', str(shots), 'docs/biology-design-validation.md')
git('diff', '--cached', '--check')
git('commit', '-m', 'docs: attach native before-after screenshots and completed design verification')
design_sha = git('rev-parse', 'HEAD')
assert not git('status', '--porcelain')
verify_source(design)
git('push', '--atomic', 'origin', f'{fix_sha}:refs/heads/{FIX}', f'{design_sha}:refs/heads/{DESIGN}')
result = {'curriculum_sha': fix_sha, 'design_sha': design_sha,
          'curriculum_implementation': implementation, 'design_implementation': design_implementation,
          'curriculum_run': BASE_RUN, 'design_run': args.design_run}
print(json.dumps(result, indent=2))
Path(os.environ['RUNNER_TEMP'], 'publication.json').write_text(json.dumps(result, indent=2) + '\n')
with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
    for key in ('curriculum_sha', 'design_sha'):
        output.write(f'{key}={result[key]}\n')
