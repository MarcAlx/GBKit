import Foundation

/// a super class for all audio channel
public class AudioChannel: CoreAudioChannel {
    public var id: AudioChannelId {
        get {
            return AudioChannelId.CH1 //override in sublcass
        }
    }
    
    // MARK: Clockable
    
    public var cycles: Int = 0
    public func tick(_ masterCycles: Int, _ frameCycles: Int) {
        self.cycles = self.cycles &+ GBConstants.MCycleLength
    }
    
    // MARK: CoreAudioChannel
    var apuProxy:APUProxy? = nil
    public func registerAPU(apu: APUProxy) {
        self.apuProxy = apu
    }
    
    /// register that usually controls length on channel
    fileprivate var LENGTH_REG:Short = 0x0
    /// register that usually controls Envelope (or volume for Wave)
    fileprivate var ENV_VOL_REG:Short = 0x0
    /// register that usually controls period/frequency of the channel
    fileprivate var PERIOD_REG:Short = 0x0
    /// register that triggers
    fileprivate var TRIGGER_REG:Short = 0x0
    
    /// value used to reload length
    fileprivate var LENGTH_RELOAD:Int {
        GBConstants.DefaultLengthTimer[self.id.rawValue]
    }
    
    /// true if length is enabled
    fileprivate var lengthEnabled:Bool = false
    /// timer used for length
    fileprivate var lengthTimer:Int = 0x0
    /// channel frequency
    fileprivate var frequency:Short = 0x0
    /// timer used for frequency
    fileprivate var frequencyTimer:Short = 0
    
    public var enabled:Bool = false
    
    
    public init(){
    }
    
    public func read(address:Short) -> Byte {
        switch(address){
        case self.TRIGGER_REG:
            return 0b1011_1111
                 | (self.lengthEnabled ? 1 : 0) << 6
        default:
            //by default return 0xFF
            return 0xFF
        }
    }
    
    public func write(address:Short, value:Byte) {
        switch(address){
        case self.PERIOD_REG:
            self.frequency = (self.frequency & 0b1111_1111_0000_0000)
                           | Short(value)
            break
        case self.TRIGGER_REG:
            self.frequency = (self.frequency & 0b0000_0000_1111_1111)
                           | (Short(value & 0b0000_0111) << 8)
            self.lengthEnabled = (value & 0b0100_0000) > 1
            
            if(self.lengthTimer == 0){
                self.lengthTimer = self.LENGTH_RELOAD;
                
                if let proxy = self.apuProxy {
                    //obscure behavior, if APU next sequencer step is not length, trigger should decrement once length timer
                    if(proxy.willTickLength){
                        self.lengthTimer -= 1
                    }
                    //obscure behavior, if channel is triggered when envelope will tick length timer is incremented
                    else if(proxy.willTickEnvelope){
                        self.lengthTimer += 1
                    }
                }
            }
            
            //if bit 7 is set trigger
            if(isBitSet(.Bit_7, value)){
                self.trigger()
            }
            break
        default:
            break
        }
    }
    
    public var amplitude:Byte {
        get {
            return 0
        }
    }
    
    public func trigger(){
        self.enabled = true;
    }
    
    public func tickLength(){
        if(self.lengthEnabled && self.lengthTimer > 0){
            self.lengthTimer -= 1
            
            if(self.lengthTimer == 0){
                self.enabled = false
            }
        }
    }
    
    /// look up table for digital to analog conversion
    /// the digital range of each channel (0x0 to 0xF) is mapped to the following analog range -1 to 1 (with negative slope 0x0 is 1 and 0xF is -1)
    private let amplitudeConversionLUT:[Float] = Array(0 ... 0xF).map { 1.0 - (Float($0)/Float(0xF))*2.0  }
    
    private var _DACENabled:Bool = false
    /// if true dac is enabled, if disabled it also disables channel
    fileprivate var DACEnabled:Bool {
        get {
            self._DACENabled
        }
        set {
            self._DACENabled = newValue
            if(!newValue){
                self.enabled = false
            }
        }
    }
    
    public var analogAmplitude: Float {
        if(self.DACEnabled){
            //map Digital aplitude to its analog precomputed value (& 0xf to avoid overflow)
            return self.amplitudeConversionLUT[Int(self.amplitude & 0xF)]
        }
        return 0
    }
    
    // MARK: Component
    public func reset(){
        self.lengthTimer    = 0x0
        self.frequency      = 0x0
        self.frequencyTimer = 0
    }
}

/// a super class for channel with envelope
public class AudioChannelWithEnvelope:AudioChannel, EnvelopableChannel {
    /// true if envelope direction is up
    private var isEnvelopeDirectionUp:Bool = false
    /// envelope pace (value that re-arm timer
    private var envelopeSweepPace:Byte = 0x0
    /// channel volume
    public var volume:Byte = 0x0
    /// timer for envelope
    private var envelopeTimer:Short = 0x0
    /// value used on trigger o reset volume
    private var initialVolume:Byte = 0x0
    
    public override func reset() {
        super.reset()
        self.isEnvelopeDirectionUp = false
        self.envelopeSweepPace = 0x0
        self.volume = 0x0
        self.envelopeTimer = 0x0
        self.initialVolume = 0x0
    }
    
    public override func read(address:Short) -> Byte {
        switch(address){
        case self.ENV_VOL_REG:
            return (self.envelopeSweepPace & 0b0000_0111)
                 | (self.isEnvelopeDirectionUp ? 1 : 0) << 3
                 | (self.initialVolume << 4)
        default:
            return super.read(address: address)
        }
    }
    
    public override func write(address:Short, value:Byte) {
        switch(address){
        case self.ENV_VOL_REG:
            self.initialVolume = value>>4
            self.isEnvelopeDirectionUp = ((value & 0b0000_1000) > 0)
            self.envelopeSweepPace = value & 0b0000_0111;
            //turn off dac if 5 first bits are disabled
            self.DACEnabled = (value & 0b1111_1000 != 0)
            break
        default:
            super.write(address: address, value: value)
            break
        }
    }
 
    public func tickEnvelope(){
        //a pacing of 0 means envelope is disabled
        if(self.envelopeSweepPace != 0){
            //every tick decrease pace
            if(self.envelopeTimer>0){
                self.envelopeTimer -= 1
            }
            //it's time to apply envelope
            if(self.envelopeTimer == 0){
                self.envelopeTimer = Short(self.envelopeSweepPace) //re-arm timer with initial value (n.b needs retrigger to re-read mmu value)
                
                //envelope is only applied for a volume between 0x0 and 0xF (15)
                if(self.volume < 0xF && self.isEnvelopeDirectionUp) {
                    self.volume += 1
                }
                else if(self.volume > 0x0 && !self.isEnvelopeDirectionUp) {
                    self.volume -= 1
                }
            }
        }
    }
    
    public override func trigger(){
        super.trigger()
        self.envelopeTimer = Short(self.envelopeSweepPace)
        self.volume = self.initialVolume
    }
}

/// channel 2 is a square channel
public class Pulse:AudioChannelWithEnvelope, SquareChannel {
    public override var id: AudioChannelId {
        get {
            return AudioChannelId.CH2
        }
    }
    
    public override init(){
        super.init()
        self.LENGTH_REG  = IOAddresses.AUDIO_NR21.rawValue
        self.ENV_VOL_REG = IOAddresses.AUDIO_NR22.rawValue
        self.PERIOD_REG  = IOAddresses.AUDIO_NR23.rawValue
        self.TRIGGER_REG = IOAddresses.AUDIO_NR24.rawValue
    }
    
    /// index of duty pattern used
    private var dutyPattern:Byte = 0x0
    /// index of current step in duty pattern
    private var dutyStep:Byte = 0x0
    
    public override func reset() {
        super.reset()
        self.dutyPattern = 0x0
        self.dutyStep = 0x0
    }
    
    public override func read(address:Short) -> Byte {
        switch(address){
        case self.LENGTH_REG:
            return self.dutyPattern << 6 | 0b0011_1111
        default:
            return super.read(address: address)
        }
    }
    
    public override func write(address:Short, value:Byte) {
        switch(address){
        case self.LENGTH_REG:
            self.dutyPattern = (value >> 6)
            self.lengthTimer = self.LENGTH_RELOAD - (Int(value) & 0b0011_1111)
            break
        case self.ENV_VOL_REG:
            super.write(address: address, value: value)
            //turn off dac if 5 first bits are disabled
            self.DACEnabled = (value & 0b1111_1000 != 0)
            break
        default:
            super.write(address: address, value: value)
            break
        }
    }
    
    public override func tick(_ masterCycles: Int, _ frameCycles: Int) {
        if(self.frequencyTimer == 0){
            //duty timer is re-armed by subtracting period divider to period
            self.frequencyTimer = (Short(GBConstants.APUPeriodDivider) - self.frequency)
            
            //increment duty step (it wraps arround when overflown)
            self.dutyStep = (self.dutyStep + 1) % 8
        }
        self.frequencyTimer -= 1
    }
    
    public override var amplitude:Byte {
        get {
            if(self.enabled){
                //amplitude is equal to DutyPattern value (0 or 1) multiplied by volume (byte value)
                return GBConstants.DutyPatterns[Int(self.dutyPattern)][Int(self.dutyStep)]
                     * self.volume
            }
            return 0
        }
    }
}

/// channel 1 is same as channel 2 but with sweep
public class Sweep: Pulse, SquareWithSweepChannel{
    public override var id: AudioChannelId {
        get {
            return AudioChannelId.CH1
        }
    }
    
    private let SWEEP_REG:Short = IOAddresses.AUDIO_NR10.rawValue

    /// frequency is saved on trigger to avoid taking into account in between frequency writes
    private var sweepShadowFrequency:Short = 0
    /// sweep has its own timer
    private var sweepTimer:Byte = 0
    /// initial timer value to reload the timer with
    private var sweepPace:Byte = 0
    /// true if sweep is incremental
    private var isSweepDirectionUp:Bool = false
    /// value used for sweep computation
    private var sweepStep:Byte = 0
    /// true if swwep is enabled
    private var sweepEnabled:Bool = false
    
    public override init(){
        super.init()
        self.LENGTH_REG  = IOAddresses.AUDIO_NR11.rawValue
        self.ENV_VOL_REG = IOAddresses.AUDIO_NR12.rawValue
        self.PERIOD_REG  = IOAddresses.AUDIO_NR13.rawValue
        self.TRIGGER_REG = IOAddresses.AUDIO_NR14.rawValue
    }
    
    public override func read(address:Short) -> Byte {
        switch(address){
        case self.SWEEP_REG:
            return (self.sweepPace << 4)
                 | ((self.isSweepDirectionUp ? 0 : 1) << 3)
                 | self.sweepStep
                 | 0b1000_0000 //bit 7 is not readable
        default:
            return super.read(address: address)
        }
    }
    
    public override func write(address:Short, value:Byte) {
        switch(address){
        case self.SWEEP_REG:
            self.sweepPace          = value & 0b0111_0000
            self.isSweepDirectionUp = (value & 0b0000_1000) == 0
            self.sweepStep          = value & 0b0000_0111
            break
        default:
            super.write(address: address, value: value)
        }
    }
    
    public override func trigger() {
        super.trigger()
        
        self.loadSweepTimer()
        self.sweepShadowFrequency = self.frequency
        self.sweepEnabled = self.sweepPace > 0 || self.sweepStep > 0
        //on trigger an OOB check is performed
        if self.sweepStep > 0 {
            //Only check
            let res = self.computePeriod()
            if res.outOfBounds {
                self.enabled = false
            }
        }
    }
    
    /// computes new period using the following formula:
    ///    NewPeriod = currentPeriod ± (currentPeriod / 2^sweepStep)
    ///    n.b ± depends on isSweepDirectionUp
    ///    returns new period in res, along with indication if this value is out of bounds (11bit overflow (of NR13/NR14) or form an underflow)
    private func computePeriod() -> (newPeriod:Short, outOfBounds:Bool) {
        //sweep formula is: NewPeriod = currentPeriod ± (currentPeriod / 2^sweepStep)
        //n.b ± depends on isSweepDirectionUp
        let currentPeriod = self.sweepShadowFrequency
        let deltaPeriod = (currentPeriod / Short(pow(2.0, Double(self.sweepStep))))
        let newPeriod = self.isSweepDirectionUp ? currentPeriod + deltaPeriod
                                                : currentPeriod &- deltaPeriod
        return (newPeriod: newPeriod,
                outOfBounds: newPeriod >= 0x7FF)
    }
    
    /// ensure sweeptimer is loaded with 8 in case of pace being 0
    private func loadSweepTimer() {
        self.sweepTimer = self.sweepPace == 0 ? 8 : self.sweepPace
    }
    
    /// checks if next period computation would produce overflow/underflow if so disable channels
    /// mainly for anticiaption
    private func checkNextOutOfBounds() {
        self.enabled = !self.computePeriod().outOfBounds
    }
    
    public func tickSweep() {
        if(self.sweepTimer>0){
            self.sweepTimer -= 1
        }
        //apply sweep when timer is 0
        if(self.sweepTimer==0){
            //reload timer
            self.loadSweepTimer()
            //timer runs even is sweep is disabled but not if pace is 0
            if(self.sweepEnabled && self.sweepPace > 0){
                //compute new perdiod
                let res = self.computePeriod()
                //apply if not OOB
                if(!res.outOfBounds){
                    self.frequency = res.newPeriod
                    self.sweepShadowFrequency = res.newPeriod
                    //on apply check next OOB
                    self.checkNextOutOfBounds()
                }
                else {
                    self.enabled = false
                }
            }
        }
    }
}

/// channel 3 is a wave channel
public class Wave: AudioChannel, WaveChannel {
    public override var id: AudioChannelId {
        get {
            return AudioChannelId.CH3
        }
    }
    
    /// specific register to control wave parameter
    private let WAVE_REG:Short = IOAddresses.AUDIO_NR30.rawValue
    
    /// current sample read in wave
    private var wavePosition:Int = 0
    /// store each wave ram nibble (16byte * 2 nibbles = 32 values) Upper, Lower, Upper, Lower...
    private var waveSamples:[Byte] = Array(repeating: 0xFF, count: MMUAddressSpaces.WAVE_RAM.count * 2)
    /// index of shift to apply to wave to control output (volume)
    private var waveOutputLevel:Byte = 0x0
    
    public override init(){
        super.init()
        
        self.LENGTH_REG  = IOAddresses.AUDIO_NR31.rawValue
        self.ENV_VOL_REG = IOAddresses.AUDIO_NR32.rawValue
        self.PERIOD_REG  = IOAddresses.AUDIO_NR33.rawValue
        self.TRIGGER_REG = IOAddresses.AUDIO_NR34.rawValue
    }
    
    public override func read(address:Short) -> Byte {
        switch(address){
        case self.WAVE_REG:
            return ((self.DACEnabled ? 1 : 0) << 7) | 0b0111_1111
        case self.LENGTH_REG:
            return 0xFF
        case self.ENV_VOL_REG:
            return (self.waveOutputLevel << 5) | 0b1001_1111
        case self.PERIOD_REG:
            return 0xFF
        case MMUAddressSpaces.WAVE_RAM:
            //if wave ram is enabled read is 0xFF
            if(self.enabled){
                return 0xFF
            }
            else {
                let waveIndex = Int(address - MMUAddressSpaces.WAVE_RAM.lowerBound) * 2
                return self.waveSamples[waveIndex] << 4
                | self.waveSamples[waveIndex+1]
            }
        default:
            return super.read(address: address)
        }
    }
    
    public override func reset() {
        super.reset()
        self.wavePosition = 0
        self.waveSamples = Array(repeating: 0xFF, count: MMUAddressSpaces.WAVE_RAM.count * 2)
        self.waveOutputLevel = 0x0
    }
    
    public override func write(address:Short, value:Byte) {
        switch(address){
        case self.WAVE_REG:
            self.DACEnabled = (value & 0b1000_0000) > 0
            break
        case self.LENGTH_REG:
            self.lengthTimer = self.LENGTH_RELOAD - Int(value)
            break
        case self.ENV_VOL_REG:
            self.waveOutputLevel = (value & 0b0110_0000) >> 5
            break
        case MMUAddressSpaces.WAVE_RAM:
            //if CH3 is active wave ram write is not allowed
            if(!self.enabled){
                let waveIndex = (Int(address - MMUAddressSpaces.WAVE_RAM.lowerBound)) * 2
                self.waveSamples[waveIndex] = value >> 4
                self.waveSamples[waveIndex+1] = value & 0b0000_1111
            }
            break
        default:
            super.write(address: address, value: value)
            break
        }
    }
    
    public override func trigger() {
        super.trigger()
        self.wavePosition = 0
    }
    
    override public func tick(_ masterCycles: Int, _ frameCycles: Int) {
        if(self.frequencyTimer == 0){
            self.frequencyTimer = (Short(GBConstants.APUPeriodDivider) - self.frequency)
                                /  Short(GBConstants.WaveChannelSpeedFactor) //divide as if ticked every 4t, timer should be smaller if faster
            //update position
            self.wavePosition = (self.wavePosition + 1) % self.waveSamples.count
        }
        self.frequencyTimer -= 1
    }
    
    /// returns channel amplitude according to current wave pattern
    public override var amplitude:Byte {
        get {
            if(self.enabled){
                return (self.waveSamples[self.wavePosition] >> GBConstants.WaveShiftValue[Int(self.waveOutputLevel)])
            }
            else {
                return 0
            }
        }
    }
}

/// channel 4 is a noise channel
public class Noise: AudioChannelWithEnvelope, NoiseChannel {
    public override var id: AudioChannelId {
        get {
            return AudioChannelId.CH4
        }
    }
    
    /// used to compute frequency
    private var clockShift:Byte = 0
    /// true if noise is in short mode
    private var hasNoiseShortWidth:Bool = false
    /// divider used to compute frequency
    private var clockDivider:Byte = 0
    /// clock divisor obtained from divider
    private var clockDivisor:Int = 0
    
    /// linear feedback shift register used to produce noise
    private var LFSR:Short = 0
    
    public override init(){
        super.init()
        
        self.LENGTH_REG  = IOAddresses.AUDIO_NR41.rawValue
        self.ENV_VOL_REG = IOAddresses.AUDIO_NR42.rawValue
        self.PERIOD_REG  = IOAddresses.AUDIO_NR43.rawValue
        self.TRIGGER_REG = IOAddresses.AUDIO_NR44.rawValue
    }
    
    public override func reset() {
        super.reset()
        self.clockShift = 0
        self.hasNoiseShortWidth = false
        self.clockDivider = 0
        self.clockDivisor = 0
    }
    
    public override func read(address:Short) -> Byte {
        switch(address){
        case self.LENGTH_REG:
            return 0xFF
        case self.PERIOD_REG:
            return (self.clockShift << 4)
                 | (self.hasNoiseShortWidth ? 1 : 0) << 3
                 | (self.clockDivider & 0b0000_0111)
        default:
            return super.read(address: address)
        }
    }
    
    public override func write(address:Short, value:Byte) {
        switch(address){
        case self.LENGTH_REG:
            self.lengthTimer = self.LENGTH_RELOAD - (Int(value) & 0b0011_1111)
            break
        case self.PERIOD_REG:
            self.clockShift = (value & 0b1111_0000) >> 4
            self.hasNoiseShortWidth = (value & 0b0000_1000) > 0
            self.clockDivider = value & 0b0000_0111
            self.clockDivisor = GBConstants.APUNoiseDivisor[Int(self.clockDivider)]
            break
        default:
            super.write(address: address, value: value)
            break;
        }
    }
    
    public override func trigger() {
        super.trigger()
        self.frequencyTimer = Short(self.clockDivisor)
        //on trigger reset LFSR to 0, no relevant official doc points at a 0x7FFF reset
        self.LFSR = 0
    }
    
    override public func tick(_ masterCycles: Int, _ frameCycles: Int) {
        if(self.frequencyTimer == 0){
            //reload noise timer
            self.frequencyTimer = (Short(Short(self.clockDivisor) << self.clockShift))
            //compute LFSR bit to apply (Not XOR between bit 0 and 1)
            let xor:Short = ~(((self.LFSR & 0b10) >> 1) ^ (self.LFSR & 0b01))
            //store xor at corresponding bit according to noise width
            if(self.hasNoiseShortWidth){
                self.LFSR = clear(.Bit_7, self.LFSR)
                self.LFSR |= xor << 7
            }
            else {
                self.LFSR = clear(.Bit_15, self.LFSR)
                self.LFSR |= xor << 15
            }
            //shift LFSR by 1
            self.LFSR >>= 1
        }
        else{
            self.frequencyTimer -= 1
        }
    }
    
    /// returns channel amplitude according to current wave pattern
    public override var amplitude:Byte {
        get {
            if(self.enabled){
                //amplitude is equal to LFSR bit 0 value. 0 no volume, 1 volume (shorthand by multiplied)
                return Byte(self.LFSR & 0b0000_0000_0000_0001) * self.volume
            }
            else {
                return 0
            }
        }
    }
}
