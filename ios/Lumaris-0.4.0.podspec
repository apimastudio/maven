# One podspec, two ways of reading it.
#
# A customer gets the binary: `vendored_frameworks`, downloaded from our own
# static host. The sample in this repository gets the sources, because a
# development loop that rebuilds two XCFrameworks for every edited line is
# not a development loop.
#
# The alternative was a second, source-flavoured podspec beside this one,
# and it was rejected for the reason two build files are always rejected
# here: they drift, and the drift is only discovered by the customer. The
# file lists below are read by both modes, so a source that is missing from
# one is missing from both.
#
# sample-client/Podfile sets this; nothing else should.
LUMARIS_FROM_SOURCE = ENV['LUMARIS_DEV'] == '1'

Pod::Spec.new do |s|
  s.name             = 'Lumaris'
  s.version          = '0.4.0'
  s.summary          = 'Real-time AR makeup for iOS video calls.'
  s.description      = <<~DESC
    Face tracking, a native landmark pipeline and eight GLSL makeup layers,
    composited live onto the outgoing video of a call.
  DESC
  s.homepage         = 'https://github.com/muratdoglu/lumaris-ios-native'
  s.author           = { 'Apima' => 'info@apima.com' }
  s.license          = { :type => 'Commercial', :file => 'LICENSE' }
  # A built archive, not a git checkout, and that is the whole point of this
  # revision. The previous source handed a customer the Swift *and the C++*
  # out of a private repository -- the licence verification and the shader
  # decryption included. Android has never done that: it publishes a
  # compiled AAR to maven.apimastudio.com and the source stays here.
  #
  # Same host, same shape: a static file tree served over HTTPS, published
  # by a git push, with no repository server, no account and no password for
  # a customer to be given. tools/build-xcframework.sh makes this file;
  # tools/publish-cocoapods.sh puts it there.
  s.source           = if LUMARIS_FROM_SOURCE
    { :git => 'https://github.com/muratdoglu/lumaris-ios-native.git', :tag => s.version.to_s }
  else
    { :http => "https://maven.apimastudio.com/ios/Lumaris-#{s.version}.zip" }
  end

  # iOS 15, and the floor is set by a dependency rather than by us. App
  # Attest -- which the licence design leans on for device integrity -- only
  # needs 14, which is what this said until `pod lib lint` refused to
  # resolve: MediaPipeTasksVision raised its own minimum to iOS 15 at
  # 0.10.33 and has stayed there through 1.0.0. Holding 14 would mean
  # pinning MediaPipe at 0.10.21, the last release that allowed it, and an
  # old face tracker is a worse thing to ship than a floor no real device
  # is below.
  s.ios.deployment_target = '15.0'
  s.swift_version = '5.9'

  # MediaPipeTasksVision is a static framework, so this pod has to be one
  # too. Without it, a customer using `use_frameworks!` -- the default in a
  # Swift app -- hits "target has transitive dependencies that include
  # statically linked binaries" at `pod install`, which is a failure in
  # their project caused by an omission in ours.
  s.static_framework = true

  # CocoaPods rather than Swift Package Manager, and the reason is the
  # dependencies rather than preference: MediaPipe and Agora both ship
  # through CocoaPods and neither offers an SPM package. It is also what the
  # market does -- Banuba and FaceUnity are both distributed this way, so a
  # customer integrating this is doing something their team has done before.
  #
  # Package.swift stays in the repository as the development and test
  # harness: `swift test` runs the licence core on macOS in seconds, with no
  # simulator, and that loop found real porting bugs. This podspec is what
  # ships; that one is how it gets checked. They share sources rather than
  # copying them, so the two cannot describe different code -- but they can
  # describe different *subsets*, and this file is the authority on what a
  # customer receives.

  # Carried into the pod so the MIT obligation the shaders and the NURBS
  # evaluator come with travels with the code that discharges it. LICENSE
  # points at these; shipping one without the other would be a broken
  # notice. Both are in the archive, at its root.
  s.preserve_paths = 'third_party/**/*', 'LICENSE'

  # ---------------------------------------------------------------------
  # Core: everything except a call provider.
  #
  # A customer on their own video stack, or on a provider that is not Agora,
  # takes this and nothing else. It is the default subspec, so `pod
  # 'Lumaris'` means exactly this -- and it will keep meaning exactly this
  # when the Agora subspec below is enabled, which is why Core is a subspec
  # today rather than bare source files that would have to move later.
  s.subspec 'Core' do |core|
    # The binary. Device and simulator slices, built with module stability
    # so a customer's Xcode update does not break their build, and static so
    # MediaPipe's symbols stay undefined until their app links it -- the
    # first build of this framework was dynamic and swallowed Google's
    # binary whole, 78MB of somebody else's code under our name.
    if LUMARIS_FROM_SOURCE
      core.source_files = [
        'sdk/Sources/LumarisCore/**/*.{c,cpp,h}',
        'sdk/Sources/Lumaris/**/*.swift',
        # The MediaPipe half. Separate directory, not separate module:
        # CocoaPods compiles both into one target, while Package.swift
        # compiles only the first -- which is what keeps `swift test` a
        # seconds-long loop with no simulator and no 3.6MB model. The
        # `FaceTracker` protocol lives on the dependency-free side so the
        # session and renderer can name it without naming MediaPipe.
        'sdk/Sources/LumarisTracking/**/*.swift',
        # Carried byte-for-byte so they can be diffed against upstream,
        # which is why their warnings are silenced rather than fixed.
        'sdk/Sources/LumarisVendored/**/*.{c,h}',
      ]
      core.public_header_files = 'sdk/Sources/LumarisCore/include/*.h'
      core.private_header_files = 'sdk/Sources/LumarisVendored/include/*.h'
      core.pod_target_xcconfig = {
        'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
        'CLANG_CXX_LIBRARY' => 'libc++',
        # The C++ sources include each other by plain filename, as they do
        # in the Android CMake build, so they are compiled from one search
        # path rather than being rewritten to please a second build system.
        'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/sdk/Sources/LumarisCore" "$(PODS_TARGET_SRCROOT)/sdk/Sources/LumarisVendored/include"',
        # OpenGL ES is deprecated on iOS and has been since iOS 12; it is
        # still shipped and still works, which is what docs/RENDERER.md's
        # decision rests on. Apple's own opt-out is this define, named in
        # the deprecation message itself.
        'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) GLES_SILENCE_DEPRECATION=1',
      }
    else
      core.vendored_frameworks = 'LumarisSDK.xcframework'
    end

    # The face landmark model, byte-for-byte the same file the Android SDK
    # ships (sha256 64184e22...bc9ff). Not re-downloaded from Google and not
    # a different revision: the pipeline's landmark indices, the NURBS
    # control points and the shaders all assume this model's 478-point
    # topology, so "a face landmarker" is not interchangeable with "the face
    # landmarker this was built against".
    #
    # Listed as directories rather than as a `**/*` glob, and that is not a
    # style choice. CocoaPods copies a glob's matches into the bundle root,
    # flattening the tree -- and every one of the eight layers has a file
    # called vertex.glsl.enc, so sixteen files collapsed onto two names and
    # the build failed with "Multiple commands produce
    # .../Lumaris.bundle/vertex.glsl.enc". A bare directory is treated as a
    # folder reference and copied whole, which keeps shaders/lip/vertex.glsl.enc
    # addressable as itself.
    #
    # They sit beside the framework rather than inside it because
    # ShaderAssetLoader already looks for `Lumaris.bundle` in the app and
    # next to the framework, and because a shader a customer can see is a
    # shader a customer can report a bug about. What is *not* visible is the
    # thing that matters: they are encrypted, and the key comes from the
    # licence service through the C++ compiled into the binary above.
    resources = if LUMARIS_FROM_SOURCE
      ['sdk/Resources/shaders', 'sdk/Resources/models', 'sdk/Resources/accessories']
    else
      ['Resources/shaders', 'Resources/models', 'Resources/accessories']
    end
    core.resource_bundles = { 'Lumaris' => resources }

    core.libraries = 'c++'
    core.frameworks = 'OpenGLES', 'AVFoundation', 'CoreVideo', 'CoreMedia', 'Security'

    core.dependency 'MediaPipeTasksVision', '~> 1.0'
  end

  # ---------------------------------------------------------------------
  # The vendored crypto -- TweetNaCl and tiny-AES -- has no subspec any
  # more. It is compiled into the framework, which is where it belongs: it
  # is what verifies the licence grant and decrypts the shaders, and a
  # customer who can read it can study how to forge one. The MIT notice it
  # comes with still ships, in third_party/, because the obligation travels
  # with the binary that contains the code.

  # ---------------------------------------------------------------------
  # Agora: the adapter, and the only thing that would link Agora.
  #
  # Declared now that LumarisAgoraVideo exists and actually publishes
  # frames. It stayed commented out until then on purpose: a subspec whose
  # source glob matches nothing is a lint error, and a stub that compiles
  # but does nothing is worse -- it would let a customer integrate against
  # an adapter that silently publishes nothing. Nothing about
  # `pod 'Lumaris'` changes now that this is here; a customer writes
  # `pod 'Lumaris/Agora'` if they want it and never links Agora otherwise.
  #
  # On Android this dependency is declared `api(...)` on the single module,
  # so every customer pulls Agora transitively whether they use it or not.
  # Splitting it here is a deliberate improvement rather than a port: a
  # customer writes `pod 'Lumaris/Agora'` if they want it and never sees it
  # otherwise.
  #
  # Thin by design, as on Android, where LumarisAgoraVideo delegates pause,
  # applyLook and switchCamera straight through to LumarisCallSession and
  # adds only track creation and the frame push.
  #
  s.subspec 'Agora' do |agora|
    # 68KB against the core's 7MB, and it is in the same archive because a
    # podspec may name exactly one source. What matters is not in the
    # download: `AgoraRtcEngine_iOS` is declared *here*, so a customer who
    # writes `pod 'Lumaris'` never resolves it, never links it, and never
    # ships it. This framework sits unused in their Pods directory and
    # nothing references it.
    if LUMARIS_FROM_SOURCE
      agora.source_files = 'sdk/Sources/LumarisAgora/**/*.swift'
    else
      agora.vendored_frameworks = 'LumarisAgora.xcframework'
    end
    agora.dependency 'Lumaris/Core'
    agora.dependency 'AgoraRtcEngine_iOS', '~> 4.6'
  end

  # ---------------------------------------------------------------------
  # There is no test_spec here, and that is a blocker rather than a choice.
  #
  # Tests that touch the tracker cannot live in sdk/Tests/LumarisTests --
  # Package.swift compiles that suite and has no MediaPipe. A CocoaPods test
  # spec is the right home, and `pod lib lint` runs one as part of
  # validation, so it would also be the only place a test could see the
  # dependency a customer actually gets.
  #
  # It does not link on this toolchain. Any target here that links XCTest
  # fails with:
  #
  #   ld: warning: Could not parse or use implicit file
  #   '.../SwiftUICore.framework/SwiftUICore.tbd': cannot link directly with
  #   'SwiftUICore' because product being built is not an allowed client of it
  #   clang: error: linker command failed with exit code 1
  #
  # Nothing in this pod imports SwiftUI. The autolink record is in neither
  # our framework nor MediaPipe's binaries -- both checked with `strings` --
  # and the pod itself, the app target, and the SPM suite all build and link
  # cleanly. Only the XCTest-linking bundle fails, which points at Xcode
  # 26.5's own XCTest rather than at anything here.
  #
  # Ruled out, each with a full lint: dropping requires_app_host; removing
  # UIKit from the test sources; EAGER_LINKING = NO; linking SwiftUI
  # explicitly so the reexport resolves through an allowed client.
  #
  # An app-hosted XCTest bundle in sample-client was tried too, and fails
  # differently and more decisively (2026-09-09). It links and builds, but
  # the process aborts as the bundle loads:
  #
  #   The test runner crashed before establishing connection ...
  #   absl::log_internal::LogMessage::FailWithoutStackTrace()
  #
  # The bundle carries 9,773 MediaPipe and abseil symbols of its own -- with
  # `inherit! :search_paths` and with no import of this pod at all -- so the
  # process ends up with two copies of a statically linked MediaPipe, and
  # abseil's own duplicate-registration check kills it. That is
  # `static_framework = true` doing exactly what it says; it is not
  # something a build setting can talk it out of.
  #
  # So the answer is not a better test target. It is to keep logic out of
  # files that only iOS compiles: TextureDecoder was split out of
  # GLTextureLoader for precisely this reason, and the flip bug it now pins
  # is testable on macOS in milliseconds because CoreGraphics is there too.
  # What is left behind the GLES guard is one glTexImage2D of a buffer that
  # is already correct.
  #
  # The tests are written and kept in sdk/Tests/LumarisIntegrationTests/ --
  # see the README there. They are not currently executed anywhere, so
  # nothing in this repository should be read as evidence that MediaPipe
  # runs. What is verified is that it *compiles*: MediaPipeFaceTracker.swift
  # is built against the real headers on every lint.

  s.default_subspecs = 'Core'
end
