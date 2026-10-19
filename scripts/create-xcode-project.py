from pathlib import Path
import hashlib
root = Path(__file__).resolve().parent.parent
files = sorted(root.glob('Sources/**/*.swift'))
def uid(s): return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
entries=[]
def add(key, body): entries.append(f'{uid(key)} = {{ {body} }};')
for f in files:
    p=str(f.relative_to(root))
    add(p, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{p}"; sourceTree = "<group>";')
    add(p+'-build',f'isa = PBXBuildFile; fileRef = {uid(p)};')
add('app-icon', 'isa = PBXFileReference; lastKnownFileType = folder.iconcomposer.icon; name = IconShadow.icon; path = Artwork/IconShadow.icon; sourceTree = "<group>";')
add('app-icon-build', f'isa = PBXBuildFile; fileRef = {uid("app-icon")};')
add('lucide-license', 'isa = PBXFileReference; lastKnownFileType = text; name = Lucide-LICENSE.txt; path = Sources/IconShadow/Resources/ThirdParty/Lucide-LICENSE.txt; sourceTree = "<group>";')
add('lucide-license-build', f'isa = PBXBuildFile; fileRef = {uid("lucide-license")};')
add('project-license', 'isa = PBXFileReference; lastKnownFileType = text; path = LICENSE; sourceTree = "<group>";')
add('project-license-build', f'isa = PBXBuildFile; fileRef = {uid("project-license")};')
add('product','isa = PBXFileReference; explicitFileType = wrapper.application; path = "Icon Shadow.app"; sourceTree = BUILT_PRODUCTS_DIR;')
add('group', 'isa = PBXGroup; children = (' + ','.join([uid(str(f.relative_to(root))) for f in files] + [uid('app-icon'), uid('strings'), uid('lucide-license'), uid('project-license'), uid('products')]) + '); sourceTree = "<group>";')
add('products',f'isa = PBXGroup; name = Products; children = ({uid("product")}); sourceTree = "<group>";')
add('sources','isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ('+','.join(uid(str(f.relative_to(root))+'-build') for f in files)+'); runOnlyForDeploymentPostprocessing = 0;')
add('frameworks','isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
for lang in ['en', 'zh-Hans']:
    key = 'strings-' + lang
    add(key, f'isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = "{lang}"; path = "Sources/IconShadow/Resources/{lang}.lproj/Localizable.strings"; sourceTree = "<group>";')
add('strings', f'isa = PBXVariantGroup; children = ({uid("strings-en")},{uid("strings-zh-Hans")}); name = Localizable.strings; sourceTree = "<group>";')
add('strings-build', f'isa = PBXBuildFile; fileRef = {uid("strings")};')
add('resources',f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({uid("strings-build")},{uid("app-icon-build")},{uid("lucide-license-build")},{uid("project-license-build")}); runOnlyForDeploymentPostprocessing = 0;')
for cfg in ['Debug','Release']:
    add('project-'+cfg, 'isa = XCBuildConfiguration; name = '+cfg+'; buildSettings = { SDKROOT = macosx; MACOSX_DEPLOYMENT_TARGET = 14.0; CLANG_ENABLE_MODULES = YES; SWIFT_VERSION = 6.0; SWIFT_STRICT_CONCURRENCY = complete; };')
    optimization = '-Onone' if cfg=='Debug' else '-O'
    add('target-'+cfg, 'isa = XCBuildConfiguration; name = '+cfg+'; buildSettings = { PRODUCT_NAME = "Icon Shadow"; PRODUCT_BUNDLE_IDENTIFIER = "dev.cinmou.IconShadow"; INFOPLIST_FILE = Info.plist; ASSETCATALOG_COMPILER_APPICON_NAME = IconShadow; CODE_SIGN_STYLE = Automatic; CODE_SIGN_IDENTITY = "-"; ENABLE_APP_SANDBOX = NO; SWIFT_OPTIMIZATION_LEVEL = "'+optimization+'"; COMBINE_HIDPI_IMAGES = YES; };')
for name in ['project','target']:
    add(name+'-configs',f'isa = XCConfigurationList; buildConfigurations = ({uid(name+"-Debug")},{uid(name+"-Release")}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
add('target',f'isa = PBXNativeTarget; buildConfigurationList = {uid("target-configs")}; buildPhases = ({uid("sources")},{uid("frameworks")},{uid("resources")}); buildRules = (); dependencies = (); name = IconShadow; productName = "Icon Shadow"; productReference = {uid("product")}; productType = "com.apple.product-type.application";')
add('project',f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2700; }}; buildConfigurationList = {uid("project-configs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; knownRegions = (en, Base, "zh-Hans"); mainGroup = {uid("group")}; productRefGroup = {uid("products")}; projectDirPath = ""; projectRoot = ""; targets = ({uid("target")});')
p=root/'IconShadow.xcodeproj'
p.mkdir(exist_ok=True)
(p/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(entries)+'\n}; rootObject = '+uid('project')+'; }\n')
scheme=p/'xcshareddata/xcschemes';scheme.mkdir(parents=True,exist_ok=True)
(scheme/'IconShadow.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('target')}" BuildableName="Icon Shadow.app" BlueprintName="IconShadow" ReferencedContainer="container:IconShadow.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('target')}" BuildableName="Icon Shadow.app" BlueprintName="IconShadow" ReferencedContainer="container:IconShadow.xcodeproj"/></BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release"/><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
