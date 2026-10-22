#!/usr/bin/env python3
"""Generate a dependency-free Xcode project; run after adding Swift source files."""
from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT / "ios"
def uid(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()

def generate():
    sources = sorted((IOS / "StandUp").rglob("*.swift"))
    entries = []
    def obj(name, value):
        entries.append(f"\t\t{uid(name)} = {{ {value} }};")
    source_builds = []
    refs = []
    for path in sources:
        name = path.relative_to(IOS).as_posix()
        ref, build = "ref:" + name, "build:" + name
        obj(ref, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{name}"; sourceTree = "<group>";')
        obj(build, f"isa = PBXBuildFile; fileRef = {uid(ref)};")
        refs.append(uid(ref))
        source_builds.append(uid(build))
    obj("assets", 'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = StandUp/Assets.xcassets; sourceTree = "<group>";')
    obj("assetBuild", f"isa = PBXBuildFile; fileRef = {uid('assets')};")
    obj("plist", 'isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = StandUp/Info.plist; sourceTree = "<group>";')
    obj("product", 'isa = PBXFileReference; explicitFileType = wrapper.application; path = StandUp.app; sourceTree = BUILT_PRODUCTS_DIR;')
    refs += [uid("assets"), uid("plist"), uid("products")]
    obj("mainGroup", f'isa = PBXGroup; children = ({", ".join(refs)}); sourceTree = "<group>";')
    obj("products", f'isa = PBXGroup; children = ({uid("product")}); name = Products; sourceTree = "<group>";')
    obj("sources", f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({", ".join(source_builds)}); runOnlyForDeploymentPostprocessing = 0;')
    obj("resources", f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({uid("assetBuild")}); runOnlyForDeploymentPostprocessing = 0;')
    obj("frameworks", 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
    obj("target", f'isa = PBXNativeTarget; buildConfigurationList = {uid("targetConfigs")}; buildPhases = ({uid("sources")}, {uid("frameworks")}, {uid("resources")}); buildRules = (); dependencies = (); name = StandUp; productName = StandUp; productReference = {uid("product")}; productType = "com.apple.product-type.application";')
    obj("project", f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1540; TargetAttributes = {{ {uid("target")} = {{ CreatedOnToolsVersion = 15.4; }}; }}; }}; buildConfigurationList = {uid("projectConfigs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = "zh-Hans"; hasScannedForEncodings = 0; knownRegions = ("zh-Hans", en, Base); mainGroup = {uid("mainGroup")}; productRefGroup = {uid("products")}; projectDirPath = ""; projectRoot = ""; targets = ({uid("target")});')
    for level in ["project", "target"]:
        for mode in ["Debug", "Release"]:
            if level == "project":
                settings = 'ALWAYS_SEARCH_USER_PATHS = NO; CLANG_ENABLE_MODULES = YES; CLANG_ENABLE_OBJC_ARC = YES; SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SWIFT_VERSION = 5.0;'
                settings += ' SWIFT_OPTIMIZATION_LEVEL = "-Onone"; DEBUG_INFORMATION_FORMAT = dwarf; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;' if mode == "Debug" else ' SWIFT_OPTIMIZATION_LEVEL = "-O"; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym"; VALIDATE_PRODUCT = YES;'
            else:
                settings = 'ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; CODE_SIGN_STYLE = Automatic; GENERATE_INFOPLIST_FILE = NO; INFOPLIST_FILE = StandUp/Info.plist; PRODUCT_BUNDLE_IDENTIFIER = com.l33klin.StandUp; PRODUCT_NAME = "$(TARGET_NAME)"; SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"; SUPPORTS_MACCATALYST = NO; TARGETED_DEVICE_FAMILY = 1; ENABLE_PREVIEWS = YES;'
            obj(level + mode, f'isa = XCBuildConfiguration; buildSettings = {{ {settings} }}; name = {mode};')
        obj(level + "Configs", f'isa = XCConfigurationList; buildConfigurations = ({uid(level + "Debug")}, {uid(level + "Release")}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
    project = IOS / "StandUp.xcodeproj"
    project.mkdir(exist_ok=True)
    (project / "project.pbxproj").write_text('// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n' + '\n'.join(entries) + f'\n\t}};\n\trootObject = {uid("project")};\n}}\n')
    scheme = project / "xcshareddata/xcschemes/StandUp.xcscheme"
    scheme.parent.mkdir(parents=True, exist_ok=True)
    ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid("target")}" BuildableName="StandUp.app" BlueprintName="StandUp" ReferencedContainer="container:StandUp.xcodeproj"/>'
    scheme.write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1540" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES"><Testables/></TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" useCustomWorkingDirectory="NO"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/>
 <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
    print(f"Generated {project} ({len(sources)} Swift files)")

if __name__ == "__main__":
    generate()
