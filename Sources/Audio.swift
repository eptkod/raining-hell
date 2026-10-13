import AppKit
import AVFoundation

/// Original synthesized placeholder audio. UI, graphics, and sound are subject to change.
///
/// Players are created once per sound file and reused. Losing focus or pausing changes volumes
/// only: the ambient loop keeps running silently and effects in flight are muted and left to
/// finish, so a Space switch never stops or starts a player. Pausing the ambient player on every
/// Space switch, and stopping every effect with it, preceded each desktop-switch crash.
final class GameAudio {
    static let variants: [SoundCue:Int] = [.shot:4,.explosion:4,.collapse:3,.rubble:3,.glass:3,.step:4,.deploy:1,.order:1,.cease:1,.select:1,.pause:1,.reset:1,.plane:1,.jet:1,.gun:1]
    /// Most copies of one sound file that can overlap before the oldest is cut off.
    static let copies = 4
    private var samples: [SoundCue:[Data]] = [:]
    /// Reusable players for each sound file, keyed by cue and variant.
    private var pool: [SoundCue:[[AVAudioPlayer]]] = [:]
    private var voices: [AVAudioPlayer] = []
    private var lastPlayed: [SoundCue:Double] = [:]
    private var sequence: [SoundCue:Int] = [:]
    private var ambient: AVAudioPlayer?
    private let silentPreview = CommandLine.arguments.contains("--screenshot")
    private var active = true
    private var paused = false
    private(set) var available = false
    private(set) var muted = UserDefaults.standard.bool(forKey:"audioMuted")
    private(set) var volume: Float = UserDefaults.standard.object(forKey:"audioVolume") == nil ? 0.5 : UserDefaults.standard.float(forKey:"audioVolume")
    init() {
        volume = max(0,min(1,volume))
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("Sounds") else { return }
        do {
            for (cue,count) in Self.variants {
                samples[cue] = try (0..<count).map { try Data(contentsOf:root.appendingPathComponent("\(cue.rawValue)\($0).wav")) }
                pool[cue] = Array(repeating:[],count:count)
            }
            ambient = try AVAudioPlayer(contentsOf:root.appendingPathComponent("ambient0.wav"))
            ambient?.numberOfLoops = -1; ambient?.volume = 0; ambient?.prepareToPlay()
            available = true
            if !silentPreview { ambient?.play() }
            sync(paused:false,active:NSApp.isActive)
        } catch { NSLog("Raining Hell audio unavailable: %@",error.localizedDescription) }
    }
    func sync(paused:Bool,active:Bool) {
        let interrupted = self.active && !active || !self.paused && paused
        self.paused=paused; self.active=active
        if interrupted { silenceEffects() }
        // The ambient loop keeps running silently rather than pausing, so leaving and returning
        // to the game's Space never stops or restarts it.
        ambient?.volume = silentPreview || muted || paused || !active ? 0 : volume*0.35
        if !silentPreview && ambient?.isPlaying == false { ambient?.play() }
        voices.removeAll { !$0.isPlaying }
    }
    func stopEffects() { voices.forEach{$0.stop()}; voices.removeAll(); lastPlayed.removeAll() }
    /// Mutes the effects in flight and lets them run out. Stopping a player tears down its audio
    /// queue, so this is used instead of `stopEffects` when the game loses focus or pauses.
    private func silenceEffects() { voices.forEach{$0.volume=0}; lastPlayed.removeAll() }
    func toggleMute() {
        muted.toggle(); UserDefaults.standard.set(muted,forKey:"audioMuted")
        if muted { stopEffects() }
        sync(paused:paused,active:active)
    }
    func adjustVolume(_ delta:Float) {
        volume=max(0,min(1,volume+delta)); UserDefaults.standard.set(volume,forKey:"audioVolume")
        // Stop old voices so a volume reduction takes effect immediately.
        stopEffects(); sync(paused:paused,active:active)
    }
    /// An idle player for this sound file, creating one only until the file has `copies` of them.
    private func player(_ cue:SoundCue,_ variant:Int) -> AVAudioPlayer? {
        let players = pool[cue]![variant]
        if let idle = players.first(where:{ !$0.isPlaying }) { return idle }
        if players.count < Self.copies, let made = try? AVAudioPlayer(data:samples[cue]![variant]) {
            pool[cue]![variant].append(made); return made
        }
        // Every copy is busy: cut off the one that started first.
        guard let oldest = voices.first(where:{ players.contains($0) }) else { return players.first }
        oldest.stop(); voices.removeAll { $0 === oldest }
        return oldest
    }
    func play(_ event:SoundEvent) {
        guard !silentPreview && available && !muted && active && volume > 0, let bank=samples[event.cue], !bank.isEmpty else { return }
        let now=ProcessInfo.processInfo.systemUptime
        let gap:Double
        switch event.cue {
        case .shot: gap=0.055
        case .step: gap=0.1
        case .explosion,.glass: gap=0.09
        case .collapse: gap=0.6
        case .rubble: gap=0.16
        default: gap=0.04
        }
        if now-(lastPlayed[event.cue] ?? -100) < gap { return }
        lastPlayed[event.cue]=now
        voices.removeAll{!$0.isPlaying}
        // Bound overlap during large squad volleys and cascading collapses.
        if voices.count >= 16 { voices.removeFirst().stop() }
        let next=sequence[event.cue,default:0]; sequence[event.cue]=next+1
        guard let player=player(event.cue,next%bank.count) else { return }
        let gain:Float
        switch event.cue {
        case .shot: gain=0.32
        case .explosion: gain=0.55
        case .collapse: gain=0.43
        case .rubble: gain=0.28
        case .glass: gain=0.3
        case .step: gain=0.3
        case .plane: gain=0.42
        case .jet: gain=0.5
        case .gun: gain=0.62
        default: gain=0.5
        }
        player.volume=volume*gain*Float(max(0,min(1,event.gain)))
        player.pan=Float(max(-0.8,min(0.8,((event.x ?? 720)-720)/900)))
        let combined = voices.reduce(player.volume) { $0 + $1.volume }
        if combined > 0.9 {
            let factor:Float = 0.9/combined
            for voice in voices { voice.volume *= factor }
            player.volume *= factor
        }
        player.currentTime = 0
        player.prepareToPlay()
        if player.play() { voices.append(player) }
    }
}
