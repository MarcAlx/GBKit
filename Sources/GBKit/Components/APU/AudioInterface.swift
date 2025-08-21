///maps each Audio channel to an int value, ease further indexing
public enum AudioChannelId:Int {
    case CH1 = 0
    case CH2 = 1
    case CH3 = 2
    case CH4 = 3
}

/// acts as a proxy over apu state, distinguished from AudioInterface as it doesn't interract with registers
public protocol APUProxy {
    ///true if APU is enabled
    var isAPUEnabled:Bool {get set}
    
    ///true if channel 1 is enabled
    var isCH1Enabled:Bool {get set}
    
    ///true if channel 2 is enabled
    var isCH2Enabled:Bool {get set}
    
    ///true if channel 3 is enabled
    var isCH3Enabled:Bool {get set}
    
    ///true if channel 4 is enabled
    var isCH4Enabled:Bool {get set}
    
    /// true if length will  ticked during next step of sequencer
    var willTickLength:Bool {get}
    
    /// true if enveloppe will  ticked during next step of sequencer
    var willTickEnvelope:Bool {get}
    
    /// channel 1
    var channel1:SquareWithSweepChannel {get}
    /// channel 2
    var channel2:SquareChannel {get}
    /// channel 3
    var channel3:WaveChannel {get}
    /// channel 4
    var channel4:NoiseChannel {get}
    
    /// read NR52 value
    func readNR52() -> Byte
    
    /// wrtie NR52 value
    func writeNR52(value:Byte)
}

/// ease access to audio registers
public protocol AudioInterface {
    /// returns information about each channel L/R audio panning, if true the corresponding channel componnent L/R is enabled (it's hard panning on/off no seamless transition here)
    func getAPUChannelPanning() -> (CH4_L:Bool,
                                    CH3_L:Bool,
                                    CH2_L:Bool,
                                    CH1_L:Bool,
                                    CH4_R:Bool,
                                    CH3_R:Bool,
                                    CH2_R:Bool,
                                    CH1_R:Bool)/*n.b order is mismatched to match corresponding bit i register, mismatch in swift's tuple order is deprecated*/
 
    /// returns master volume (for L and R)
    func getMasterVolume() -> (L:Byte, R:Byte)
    
    /// returns VIN panning
    func getVINPanning() -> (L:Bool, R:Bool)
    
    ///register an apu for use
    func registerAPU(apu:APUProxy)
}


///to avoid nullable
struct DefaultAPUProxy: APUProxy {
    var isAPUEnabled: Bool = false
    var willTickLength: Bool = false
    var willTickEnvelope: Bool = false
    var isCH1Enabled: Bool = false
    var isCH2Enabled: Bool = false
    var isCH3Enabled: Bool = false
    var isCH4Enabled: Bool = false
    var channel1:SquareWithSweepChannel = Sweep()
    var channel2:SquareChannel = Pulse()
    var channel3:WaveChannel = Wave()
    var channel4:NoiseChannel = Noise()
    func readNR52() -> Byte {
        return 0xFF
    }
    func writeNR52(value:Byte) {
    }
}
