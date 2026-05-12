//
//  ProSwingCatalogTests.swift
//  golf-sync-swingTests
//

import Testing
import AVFoundation
@testable import golf_sync_swing

struct ProSwingCatalogTests {

    @Test("Pro swing catalog includes the curated local dataset library")
    func proSwingCatalogIncludesCuratedDatasetLibrary() {
        let expectedFilenames: Set<String> = [
            "adam-scott-driver",
            "brooke-henderson-iron",
            "bryson-dechambeau-driver",
            "bubba-watson-iron",
            "charley-hull-driver",
            "dustin-johnson-fairway",
            "hyo-joo-kim-driver",
            "inbee-park-driver",
            "justin-rose-driver",
            "lexi-thompson-driver",
            "lydia-ko-driver",
            "michelle-wie-driver",
            "minjee-lee-driver",
            "phil-mickelson-wedge",
            "rickie-fowler-driver",
            "rory-mcilroy-driver",
            "tiger-woods-driver",
            "tiger-woods-wedge",
            "tony-finau-iron",
        ]

        let actualFilenames = Set(ProSwingCatalog.all.map(\.bundleFilename))

        #expect(actualFilenames == expectedFilenames)
    }

    @Test("Pro swing markers include at least 1.5 seconds before and after impact")
    func proSwingsIncludeContextAroundImpact() {
        for descriptor in ProSwingCatalog.all {
            let preImpact = descriptor.contactTime - descriptor.startTime
            let postImpact = descriptor.endTime - descriptor.contactTime

            #expect(preImpact >= 1.5, "\(descriptor.bundleFilename) pre-impact context is too short")
            #expect(postImpact >= 1.5, "\(descriptor.bundleFilename) post-impact context is too short")
            #expect(descriptor.startTime >= 0, "\(descriptor.bundleFilename) starts before the clip")
            #expect(descriptor.endTime <= descriptor.duration, "\(descriptor.bundleFilename) ends after the clip")
        }
    }

    @Test("Bundled pro swing assets use a 3:2 landscape crop")
    func proSwingAssetsUseThreeByTwoLandscapeCrop() async throws {
        for descriptor in ProSwingCatalog.all {
            let url = proSwingAssetURL(named: descriptor.bundleFilename)
            let size = try await videoDisplaySize(url: url)
            let ratio = size.width / size.height

            #expect(abs(ratio - 1.5) < 0.01, "\(descriptor.bundleFilename) is \(size.width)x\(size.height), expected 3:2")
        }
    }

    private func proSwingAssetURL(named filename: String) -> URL {
        projectRoot()
            .appendingPathComponent("golf-sync-swing")
            .appendingPathComponent("Resources")
            .appendingPathComponent("ProSwings")
            .appendingPathComponent("\(filename).mp4")
    }

    private func projectRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func videoDisplaySize(url: URL) async throws -> CGSize {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            Issue.record("Missing video track for \(url.lastPathComponent)")
            return .zero
        }
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        return size.applying(transform).absoluteSize
    }
}

private extension CGSize {
    var absoluteSize: CGSize {
        CGSize(width: abs(width), height: abs(height))
    }
}
