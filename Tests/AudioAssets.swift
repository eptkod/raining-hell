import Foundation
import AVFoundation
@main struct AudioAssets {
    static func main() throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1])
        let files=try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil).filter{$0.pathExtension == "wav"}
        guard files.count == 31 else { fatalError("Expected 31 generated sound assets, got \(files.count)") }
        for file in files {
            let player=try AVAudioPlayer(contentsOf:file)
            guard player.duration > 0.05, player.numberOfChannels == 1 else { fatalError("Invalid audio: \(file)") }
        }
        print("PASS: all 31 sound assets decode through AVFoundation")
    }
}
