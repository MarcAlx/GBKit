import Foundation

//not normalized audio sample (int value randed from 0 to 255
typealias RawAudioSample = (L:Int, R:Int)

//An audio sample that holds both L and R channel values
public typealias AudioSample = (L:Float, R:Float)

///Function to be passed that will play input sample buffer, it's your responsability to interleaved L and R channel sample
public typealias PlayCallback = (_ samples:[AudioSample]) -> Void

///Configuration to provide to APU,
public struct APUConfiguration {
    ///Audio sample rate (in Hz)
    ///n.b as in 44100Hz or 48000Hz
    public let sampleRate:Int
    
    ///Amount of sample to store
    public let bufferSize:Int
    
    ///Callback tha will be called once buffer size has been riched
    public let playback:PlayCallback
    
    public init(sampleRate: Int,
                bufferSize: Int,
                playback: PlayCallback?) {
        self.sampleRate = sampleRate
        self.bufferSize = bufferSize
        self.playback = playback!
    }
    
    public var isChannel1Enabled:Bool = true
    public var isChannel2Enabled:Bool = true
    public var isChannel3Enabled:Bool = true
    public var isChannel4Enabled:Bool = true
    public var isHPFEnabled:Bool = true
    
    ///default configuration, mainly for init purpose
    public static let DEFAULT:APUConfiguration = APUConfiguration(
        sampleRate: 44100,
        bufferSize: 256,
        playback: { _ in } )
}

public class APU: Component, Clockable, APUProxy {
    //true if enabled
    private var enabled = false
    
    ///buffer filled with 0.0 to express silence
    public private(set) var SILENT_BUFFER:[AudioSample] = []
    
    public private(set) var cycles:Int = 0
    
    private let mmu:MMU
    
    private var frameSequencerCounter:Int = 0
    
    private var frameSequencerStep:Int = 0
    
    private var hpfCapacitorL: Float = 0.0
    private var hpfCapacitorR: Float = 0.0
    private var hpfChargeFactor: Float = 0.0
    
    private var channel1:SquareWithSweepChannel
    private var channel2:SquareChannel
    private var channel3:WaveChannel
    private var channel4:NoiseChannel
    
    //shorthand
    private var channels:[CoreAudioChannel] = []
    
    //rate (in M tick) at which we sample
    private var sampleTickRate:Int = 0
    
    private var _configuration:APUConfiguration = APUConfiguration.DEFAULT
    public var configuration:APUConfiguration {
        set {
            //set value
            self._configuration = newValue
            //on configuration set update silent buffer with proper size
            self.SILENT_BUFFER = Array(0 ..< newValue.bufferSize ).map { _ in (L: 0.0, R: 0.0) }
            //reset audio buffer
            self._audioBuffer = self.SILENT_BUFFER
            //init sample rate, we will tick every sampleRate fraction of CPUSpeed (both are expressed in the same unit Hz)
            self.sampleTickRate = GBConstants.CPUSpeed / newValue.sampleRate
            //pre-compute charge factor
            self.hpfChargeFactor = self.computeHPFChargeFactor()
        }
        get {
            self._configuration
        }
    }
    
    private var _audioBuffer:[AudioSample] = []
    /// last commited audio buffer, ready to play
    public var audioBuffer:[AudioSample] {
        get {
            //return a copy to avoid concurrent access
            return self._audioBuffer.map { $0 }
        }
    }
    
    //next audio buffer
    private var nextBuffer:[AudioSample] = []
    
    //timer to generate timer
    private var sampleTimer = 0
    
    public var willTickLength:Bool {
        get {
               self.frameSequencerStep == 0
            || self.frameSequencerStep == 2
            || self.frameSequencerStep == 4
            || self.frameSequencerStep == 6
        }
    }
    
    init(mmu:MMU) {
        self.mmu = mmu
        self.channel1 = Sweep(mmu: self.mmu)
        self.channel2 = Pulse(mmu: self.mmu)
        self.channel3 = Wave (mmu: self.mmu)
        self.channel4 = Noise(mmu: self.mmu)
        self.channels = [self.channel1,
                         self.channel2,
                         self.channel3,
                         self.channel4]
        
        //ensure configuration related properties are set on init
        self.configuration = APUConfiguration.DEFAULT
        
        //register where needed
        self.mmu.registerAPU(apu: self)
        self.channel1.registerAPU(apu: self)
        self.channel2.registerAPU(apu: self)
        self.channel3.registerAPU(apu: self)
        self.channel4.registerAPU(apu: self)
    }
    
    /// initis length timer for a given channel using value from an NRX1 register
    public func initLengthTimer(_ channel: AudioChannelId, _ nrx1Value:Byte){
        //get channel index
        let chIdx:Int = channel.rawValue;
        //timer is set to Default values minus masked part of nrx1 value
        self.channels[chIdx].lengthTimer = GBConstants.DefaultLengthTimer[chIdx]
                                         - Int((nrx1Value & GBConstants.NRX1_lengthMask[chIdx]))
    }
    
    public func tick(_ masterCycles: Int, _ frameCycles: Int) {
        self.channel1.tick(masterCycles, frameCycles)
        self.channel2.tick(masterCycles, frameCycles)
        self.channel3.tick(masterCycles, frameCycles)
        self.channel4.tick(masterCycles, frameCycles)
        
        if(self.frameSequencerCounter >= GBConstants.APUFrameSequencerStepLength){
            self.stepFrameSequencer()
            self.frameSequencerCounter = 0
        }
        else {
            self.frameSequencerCounter = self.frameSequencerCounter &+ GBConstants.MCycleLength
        }
        
        self.cycles = self.cycles &+ GBConstants.MCycleLength
        self.sampleTimer += GBConstants.MCycleLength
        
        //sample timer has been reached -> sample
        if(self.sampleTimer >= self.sampleTickRate) {
            //reset timer
            self.sampleTimer = 0
            //store sample
            self.nextBuffer.append(self.sample())
            //buffer size has been reached commit
            if(self.nextBuffer.count >= self.configuration.bufferSize){
                //commit buffer
                self.commitBuffer()
                //playback
                self.configuration.playback(self.audioBuffer)
                //ready for next buffer
                self.nextBuffer = []
            }
        }
    }
    
    /// set current buffer as ready to use
    private func commitBuffer() {
        self._audioBuffer = self.nextBuffer.map {
            //apply HPF if required
            if(self.configuration.isHPFEnabled){
                return self.applyHighPassFilter($0)
            }
            return $0
        }
    }
    
    private func stepFrameSequencer(){
        switch(self.frameSequencerStep){
        case 0:
            self.channel1.tickLength()
            self.channel2.tickLength()
            self.channel3.tickLength()
            self.channel4.tickLength()
            break
        case 1:
            break
        case 2:
            self.channel1.tickLength()
            self.channel2.tickLength()
            self.channel3.tickLength()
            self.channel4.tickLength()
            self.channel1.tickSweep()
            break
        case 3:
            break
        case 4:
            self.channel1.tickLength()
            self.channel2.tickLength()
            self.channel3.tickLength()
            self.channel4.tickLength()
            break
        case 5:
            break
        case 6:
            self.channel1.tickLength()
            self.channel2.tickLength()
            self.channel3.tickLength()
            self.channel4.tickLength()
            self.channel1.tickSweep()
            break
        case 7:
            self.channel1.tickEnvelope()
            self.channel2.tickEnvelope()
            self.channel4.tickEnvelope()
            break
        default:
            break
        }
        
        //go to next step
        self.frameSequencerStep = (self.frameSequencerStep + 1) % 8
    }
    
    /// return L and R sample by mixing each channel amplitude
    func sample() -> AudioSample {
        let panning = self.mmu.getAPUChannelPanning()
        let volume  = self.mmu.getMasterVolume()
        //todo handle VIN (audio comming from cartridge)
        
        //sample to build
        var leftSample:Float  = 0;
        var rightSample:Float = 0;
        
        //apply panning
        
        //CH1
        if(self.configuration.isChannel1Enabled){
            if(panning.CH1_L){
                leftSample += self.channel1.analogAmplitude
            }
            if(panning.CH1_R){
                rightSample += self.channel1.analogAmplitude
            }
        }
        
        //CH2
        if(self.configuration.isChannel2Enabled){
            if(panning.CH2_L){
                leftSample += self.channel2.analogAmplitude
            }
            if(panning.CH2_R){
                rightSample += self.channel2.analogAmplitude
            }
        }
        
        //CH3
        if(self.configuration.isChannel3Enabled){
            if(panning.CH3_L){
                leftSample += self.channel3.analogAmplitude
            }
            if(panning.CH3_R){
                rightSample += self.channel3.analogAmplitude
            }
        }
        
        //CH4
        if(self.configuration.isChannel4Enabled) {
            if(panning.CH4_L){
                leftSample += self.channel4.analogAmplitude
            }
            if(panning.CH4_R){
                rightSample += self.channel4.analogAmplitude
            }
        }
        
        //return sample by applying master volume
        // divide each sample             by 4, as we have summed up all 4 channel amplitudes
        // divide volume multiplied value by 7, as volume is stored on 3 bits (max value = 0b111 -> 7)
        return (L: ((leftSample  / 4.0) * Float(volume.L)) / 7.0,
                R: ((rightSample / 4.0) * Float(volume.R)) / 7.0)
    }
    
    public func reset() {
        self.cycles = 0
        self.channel1.reset()
        self.channel2.reset()
        self.channel3.reset()
        self.channel4.reset()
        
        //ensure channels state matches mmu state
        let nr52 = self.mmu[IOAddresses.AUDIO_NR52.rawValue]
        self.enabled = isBitSet(ByteMask.Bit_7, nr52)
        self.channel4.enabled = isBitSet(ByteMask.Bit_3, nr52)
        self.channel3.enabled = isBitSet(ByteMask.Bit_2, nr52)
        self.channel2.enabled = isBitSet(ByteMask.Bit_1, nr52)
        self.channel1.enabled = isBitSet(ByteMask.Bit_0, nr52)
    }
    
    /// apply HPF to input sample
    private func applyHighPassFilter(_ input: AudioSample) -> AudioSample {
        let outL = input.L - hpfCapacitorL
        let outR = input.R - hpfCapacitorR
        hpfCapacitorL = input.L - outL * self.hpfChargeFactor
        hpfCapacitorR = input.R - outR * self.hpfChargeFactor
        return (L: outL, R: outR)
    }
    
    /// return HPF charge factor for current sample rate
    private func computeHPFChargeFactor() -> Float {
        return pow(GBConstants.APUHighPassFilterDefaultCharge, Float(GBConstants.CPUSpeed) / Float(configuration.sampleRate))
    }
    
    /// mark: APUProxy

    public var isAPUEnabled: Bool {
        get {
            return self.enabled
        }
        set {
            self.enabled = newValue
        }
    }

    public var isCH1Enabled: Bool {
        get {
            self.channel1.enabled
        }
        set {
            self.channel1.enabled = newValue
        }
    }

    public var isCH2Enabled: Bool {
        get {
            self.channel2.enabled
        }
        set {
            self.channel2.enabled = newValue
        }
    }

    public var isCH3Enabled: Bool {
        get {
            self.channel3.enabled
        }
        set {
            self.channel3.enabled = newValue
        }
    }

    public var isCH4Enabled: Bool {
        get {
            self.channel4.enabled
        }
        set {
            self.channel4.enabled = newValue
        }
    }
}
