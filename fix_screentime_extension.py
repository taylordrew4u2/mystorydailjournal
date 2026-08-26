#!/usr/bin/env python3
"""Converts MyStoryScreenTimeExtension to an ExtensionKit extension in
MyStoryDailyJournal.xcodeproj/project.pbxproj.

Run with Xcode CLOSED:  python3 fix_screentime_extension.py

Makes three edits, each verified to match exactly once before anything is
written (aborts untouched otherwise). A backup is saved next to the original
as project.pbxproj.backup.
"""

from pathlib import Path
import shutil
import sys

path = Path(__file__).resolve().parent / "MyStoryDailyJournal.xcodeproj" / "project.pbxproj"
text = path.read_text()

edits = [
    # 1. The Screen Time target becomes an ExtensionKit extension.
    (
        'productReference = E6887FFE67B06C26EF016B4A /* MyStoryScreenTime.appex */;\n'
        '\t\t\tproductType = "com.apple.product-type.app-extension";',
        'productReference = E6887FFE67B06C26EF016B4A /* MyStoryScreenTime.appex */;\n'
        '\t\t\tproductType = "com.apple.product-type.extensionkit-extension";',
    ),
    # 2a. Remove the appex from the PlugIns-destined Embed Foundation Extensions phase.
    (
        '\t\t\t\t1EA85C935E94D69EB4DEDACA /* MyStoryScreenTime.appex in Embed Foundation Extensions */,\n',
        '',
    ),
    # 2b. Add an Embed ExtensionKit Extensions phase that copies it into Extensions/.
    (
        '\t\t\tname = "Embed Foundation Extensions";\n'
        '\t\t\trunOnlyForDeploymentPostprocessing = 0;\n'
        '\t\t};\n'
        '/* End PBXCopyFilesBuildPhase section */',
        '\t\t\tname = "Embed Foundation Extensions";\n'
        '\t\t\trunOnlyForDeploymentPostprocessing = 0;\n'
        '\t\t};\n'
        '\t\t7E1DFA3C55AA43B19ED2C401 /* Embed ExtensionKit Extensions */ = {\n'
        '\t\t\tisa = PBXCopyFilesBuildPhase;\n'
        '\t\t\tbuildActionMask = 2147483647;\n'
        '\t\t\tdstPath = "$(EXTENSIONS_FOLDER_PATH)";\n'
        '\t\t\tdstSubfolderSpec = 16;\n'
        '\t\t\tfiles = (\n'
        '\t\t\t\t1EA85C935E94D69EB4DEDACA /* MyStoryScreenTime.appex in Embed ExtensionKit Extensions */,\n'
        '\t\t\t);\n'
        '\t\t\tname = "Embed ExtensionKit Extensions";\n'
        '\t\t\trunOnlyForDeploymentPostprocessing = 0;\n'
        '\t\t};\n'
        '/* End PBXCopyFilesBuildPhase section */',
    ),
    # 3. Run the new phase as part of the app target.
    (
        '\t\t\t\tE98BA8D782F04EA9B8E77EB7 /* Embed Foundation Extensions */,\n'
        '\t\t\t);',
        '\t\t\t\tE98BA8D782F04EA9B8E77EB7 /* Embed Foundation Extensions */,\n'
        '\t\t\t\t7E1DFA3C55AA43B19ED2C401 /* Embed ExtensionKit Extensions */,\n'
        '\t\t\t);',
    ),
]

for index, (old, new) in enumerate(edits, start=1):
    count = text.count(old)
    if count != 1:
        sys.exit(
            f"Edit {index}: expected exactly 1 match, found {count}. "
            "No changes were written — the project file differs from what this script expects."
        )
    text = text.replace(old, new)

backup = path.parent / (path.name + ".backup")
shutil.copy2(path, backup)
path.write_text(text)
print(f"Done. All 3 edits applied. Backup saved at {backup}")
