// swift-tools-version: 6.0
// The parts of NotchPrompter that the Mac app and the iPhone app share: following the voice
// through the script, the script library and the settings.
import PackageDescription

let package = Package(
    name: "NotchPrompterKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "NotchPrompterKit", targets: ["NotchPrompterKit"])],
    targets: [
        .target(name: "NotchPrompterKit", resources: [.process("Localizable.xcstrings")]),
    ],
    swiftLanguageModes: [.v5]
)
