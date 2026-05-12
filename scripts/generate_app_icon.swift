import AppKit
import Foundation

let projectDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "golf-sync-swing")
let appIconSet = projectDir.appendingPathComponent("Assets.xcassets/AppIcon.appiconset")
let iconPackage = projectDir.appendingPathComponent("AppIcon.icon")
let iconAssets = iconPackage.appendingPathComponent("Assets")
let source = appIconSet.appendingPathComponent("appicon-light.png")
let composerImage = iconAssets.appendingPathComponent("initial-icon.png")
let iconJSON = iconPackage.appendingPathComponent("icon.json")

let document = """
{
  "fill" : {
    "linear-gradient" : [
      "display-p3:0.18431,0.45882,0.37647,1.00000",
      "display-p3:0.07843,0.24706,0.20000,1.00000"
    ],
    "orientation" : {
      "start" : {
        "x" : 0.5,
        "y" : 0
      },
      "stop" : {
        "x" : 0.5,
        "y" : 0.7
      }
    }
  },
  "groups" : [
    {
      "blur-material" : 0,
      "layers" : [
        {
          "blend-mode" : "normal",
          "fill" : "none",
          "image-name" : "initial-icon.png",
          "name" : "Initial Golf Sync Swing Icon",
          "position" : {
            "scale" : 1,
            "translation-in-points" : [
              0,
              0
            ]
          }
        }
      ],
      "shadow" : {
        "kind" : "none",
        "opacity" : 0.5
      },
      "specular" : true,
      "translucency" : {
        "enabled" : false,
        "value" : 0
      }
    }
  ],
  "supported-platforms" : {
    "circles" : [
    ],
    "squares" : "shared"
  }
}
"""

try FileManager.default.createDirectory(at: iconAssets, withIntermediateDirectories: true)
try? FileManager.default.removeItem(at: composerImage)
try FileManager.default.copyItem(at: source, to: composerImage)
try document.write(to: iconJSON, atomically: true, encoding: .utf8)

print("Updated \(iconPackage.path) from \(source.path)")
