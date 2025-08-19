import Foundation

///a super class for all audio channel
public class AudioChannel: CoreAudioChannel {
    
    public var id: AudioChannelId {
        get {
            return AudioChannelId.CH1 //override in sublcass
        }
    }
    
    let mmu:MMU
    var apuProxy:APUProxy = DefaultAPUProxy()
    
    public internal(set) var cycles: Int = 0
    
    private var _enabled:Bool = false
    public var enabled:Bool{
        get {
            return self._enabled
        }
        set {
            self._enabled = newValue
        }
    }
    
    public var amplitude:Byte {
        get {
            return 0 // override in subclass
        }
    }
    
    /// look up table for digital to analog conversion
    /// the digital range of each channel (0x0 to 0xF) is mapped to the following analog range -1 to 1 (with negative slope 0x0 is 1 and 0xF is -1)
    private let amplitudeConversionLUT:[Float] = Array(0 ... 0xF).map { 1.0 - (Float($0)/Float(0xF))*2.0  }
    
    public var analogAmplitude: Float {
        //map Digital aplitude to its analog precomputed value (& 0xf to avoid overflow)
        self.amplitudeConversionLUT[Int(self.amplitude & 0xF)]
    }
    
    public init(mmu: MMU) {
        self.mmu = mmu
    }
    
    public func registerAPU(apu: APUProxy) {
        self.apuProxy = apu
    }
    
    public var lengthTimer:Int = 0
    
    public func tick(_ masterCycles: Int, _ frameCycles: Int) {
        //check mmu to check if channel is triggered
        if(self.mmu.isTriggered(self.id)){
            //if so trigger
            self.trigger()
            //reset mmu value
            self.mmu.resetTrigger(self.id)
        }
        self.cycles = self.cycles &+ GBConstants.MCycleLength
    }
        
    public func trigger() {
        //enable
        self.enabled = true
        //reset length if expired
        if(self.lengthTimer == 0){
            self.lengthTimer = GBConstants.DefaultLengthTimer[self.id.rawValue]
            //obscure behavior, if APU next sequencer step is not length, trigger should decrement once length timer
            if(!self.apuProxy.willTickLength){
                self.lengthTimer -= 1
            }
        }
    }
    
    public func tickLength() {
        if(self.lengthTimer>0 && self.mmu.isLengthEnabled(self.id)) {
            self.lengthTimer -= 1
            //when length reaches 0 it disable channel
            if(self.lengthTimer == 0){
                self.enabled = false
            }
        }
    }
    
    public func reset() {
        self.enabled = false
    }
}

///a super class for channel with envelope
public class AudioChannelWithEnvelope: AudioChannel, EnveloppableChannel{
    //channel volume, only for envelope one, (n.b wave channel has its own volume behavior)
    public internal(set) var volume:Byte = 0
    
    public var envelopeId: EnveloppableAudioChannelId {
        get {
            return EnveloppableAudioChannelId.CH1 //override in sublcass
        }
    }
    
    private var envelopePace:Byte = 0
    private var envelopeTimer:Byte = 0
    //if envelope direction is up -> true, else direction down so false
    private var isEnvelopeDirectionUp:Bool = false
    
    override public func trigger() {
        super.trigger()
        
        //init volume with initial value
        self.volume = self.mmu.getEnvelopeInitialVolume(self.envelopeId)
        //reset sweep pace
        self.envelopePace = self.mmu.getEnvelopeSweepPace(self.envelopeId)
        self.envelopeTimer = self.envelopePace
        //save envelope direction
        self.isEnvelopeDirectionUp = self.mmu.getEnvelopeDirection(self.envelopeId) == 1
    }
    
    public func tickEnvelope() {
        //a pacing of 0 means envelope is disabled
        if(self.envelopePace != 0){
            //every tick decrease pace
            if(self.envelopeTimer>0){
                self.envelopeTimer -= 1
            }
            //it's time to apply envelope
            if(self.envelopeTimer == 0){
                self.envelopeTimer = self.envelopePace //re-arm timer with initial value (n.b needs retrigger to re-read mmu value)
                
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
}

/// channel 1 is same as channel 2 but with sweep
public class Sweep: Pulse, SquareWithSweepChannel {
    override public var id: AudioChannelId {
        AudioChannelId.CH1
    }
    
    override public var squareId: DutyAudioChannelId{
        get {
            return DutyAudioChannelId.CH1
        }
    }
    
    override public var periodId: ChannelWithPeriodId{
        get {
            return ChannelWithPeriodId.CH1 //override in sublcass
        }
    }
    
    //period is saved on trigger to avoid taking into account in between period writes
    private var sweepShadowPeriod:Short = 0
    //sweep has its own timer
    private var sweepTimer:Byte = 0
    //initial timer value to reload the timer with
    private var sweepPace:Byte = 0
    //true if sweep is incremental
    private var isSweepDirectionUp:Bool = false
    //value used for sweep computation, see computePeriod()
    private var sweepStep:Byte = 0
    //if true sweep will be computed and applied
    private var sweepEnabled:Bool = false
    
    override public func tick(_ masterCycles: Int, _ frameCycles: Int) {
        super.tick(masterCycles, frameCycles)
    }
    
    override public func reset() {
        super.reset()
    }
    
    override public func trigger() {
        super.trigger()
        self.sweepShadowPeriod = self.mmu.getPeriod(self.periodId)
        self.sweepPace  = self.mmu.getSweepPace()
        self.loadSweepTimer()
        self.isSweepDirectionUp  = self.mmu.getSweepDirection() == 0
        self.sweepStep  = self.mmu.getSweepStep()
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
    
    /// ensure sweeptimer is loaded with 8 in case of pace being 0
    private func loadSweepTimer() {
        self.sweepTimer = self.sweepPace == 0 ? 8 : self.sweepPace
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
                    self.mmu.setPeriod(self.squareId, res.newPeriod)
                    self.sweepShadowPeriod = res.newPeriod
                    //on apply check next OOB
                    self.checkNextOutOfBounds()
                }
                else {
                    self.enabled = false
                }
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
        let currentPeriod = self.sweepShadowPeriod
        let deltaPeriod = (currentPeriod / Short(pow(2.0, Double(self.sweepStep))))
        let newPeriod = self.isSweepDirectionUp ? currentPeriod + deltaPeriod
                                                : currentPeriod &- deltaPeriod
        return (newPeriod: newPeriod,
                outOfBounds: newPeriod >= 0x7FF)
    }
    
    /// checks if next period computation would produce overflow/underflow if so disable channels
    /// mainly for anticiaption
    private func checkNextOutOfBounds() {
        self.enabled = !self.computePeriod().outOfBounds
    }
}

/// channel 2 is a square channel
public class Pulse: AudioChannelWithEnvelope, SquareChannel {
    
    override public var id: AudioChannelId {
        AudioChannelId.CH2
    }
    
    public var periodId: ChannelWithPeriodId {
        get {
            return ChannelWithPeriodId.CH2
        }
    }
    
    public var squareId: DutyAudioChannelId{
        get {
            return DutyAudioChannelId.CH2
        }
    }
    
    private var dutyStep:Int = 0
    private var dutyTimer:Int = 0
    
    /// returns channel amplitude according to current wave duty step
    public override var amplitude:Byte {
        get {
            if(self.enabled){
                //amplitude is equal to DutyPattern value (0 or 1) multiplied by volume (byte value)
                return GBConstants.DutyPatterns[Int(self.mmu.getDutyPattern(self.squareId))][Int(self.dutyStep)]
                     * self.volume
            }
            return 0
        }
    }
    
    override public func tick(_ masterCycles: Int, _ frameCycles: Int) {
        if(self.dutyTimer > 0){
            self.dutyTimer -= 1
        }
        if(self.dutyTimer <= 0){
            //duty timer is re-armed by subtracting period divider to period
            self.dutyTimer = (GBConstants.APUPeriodDivider - Int(self.mmu.getPeriod(self.periodId)))
            
            //increment duty step (it wraps arround when overflown)
            self.dutyStep = (self.dutyStep + 1) % 8
        }
        super.tick(masterCycles, frameCycles)
    }
    
    override public func reset() {
        super.reset()
        self.dutyTimer = 0
        self.dutyStep = 0
    }
}

/// channel 3 is a wave channel
public class Wave: AudioChannel, WaveChannel {
    override public var id: AudioChannelId {
        AudioChannelId.CH3
    }
    
    public var periodId: ChannelWithPeriodId{
        get {
            return ChannelWithPeriodId.CH3
        }
    }
    
    //current sample read in wave
    private var position:Int = 0
    //initial wave timer value to avoid update before trigger
    private var initialWaveTimer:Int = 0
    //timer at which wave is updated
    private var waveTimer:Int = 0
    //store each wave ram nibble (16byte * 2 nibbles = 32 values) Upper, Lower, Upper, Lower...
    private var wavSamples:[Byte] = Array(repeating: 0xFF, count: MMUAddressSpaces.WAVE_RAM.count * 2)
    
    override public func reset() {
        super.reset()
        self.fillWavSample()
    }
    
    /// split wave ram into 32 wav samples
    private func fillWavSample() {
        var nibblePos = 0
        for addr in MMUAddressSpaces.WAVE_RAM {
            self.wavSamples[nibblePos] = self.mmu[addr] >> 4
            nibblePos += 1
            self.wavSamples[nibblePos] = self.mmu[addr] & 0b0000_1111
            nibblePos += 1
        }
    }
    
    override public func trigger() {
        super.trigger()
        self.position = 0
        self.initialWaveTimer = (GBConstants.APUPeriodDivider - Int(self.mmu.getPeriod(self.periodId))) / GBConstants.WaveChannelSpeedFactor //divide as if ticked every 4t, timer should be smaller if faster
        self.waveTimer = self.initialWaveTimer
        self.fillWavSample()
    }
    
    override public func tick(_ masterCycles: Int, _ frameCycles: Int) {
        if(self.enabled){
            if(self.waveTimer > 0){
                self.waveTimer -= 1
            }
            
            if(self.waveTimer <= 0){
                //reload wave timer
                self.waveTimer = self.initialWaveTimer
                //update position
                self.position = (self.position + 1) % self.wavSamples.count
            }
        }
        super.tick(masterCycles, frameCycles)
    }
    
    /// returns channel amplitude according to current wave pattern
    public override var amplitude:Byte {
        get {
            if(self.enabled){
                return self.wavSamples[self.position] >> GBConstants.WaveShiftValue[Int(self.mmu.getWaveOutputLevel())]
            }
            else {
                return 0
            }
        }
    }
}

/// channel 4 is a noise channel
public class Noise: AudioChannelWithEnvelope, NoiseChannel {
    
    //timer at which noise is updated
    private var noiseTimer:Int = 0
    
    /// linear feedback shift register used to produce noise
    private var LFSR:Short = 0
    
    override public var id: AudioChannelId {
        AudioChannelId.CH4
    }
    override public func trigger() {
        super.trigger()
        //on trigger reset LFSR to 0, no relevant official doc points at a 0x7FFF reset
        self.LFSR = 0
    }
    
    override public func tick(_ masterCycles: Int, _ frameCycles: Int) {
        if(self.enabled){
            if(self.noiseTimer > 0){
                self.noiseTimer -= 1
            }
            
            if(self.noiseTimer <= 0){
                //reload noise timer
                self.noiseTimer = self.mmu.getNoiseClockDivisor() << self.mmu.getNoiseClockShift()
                //compute LFSR bit to apply (Not XOR between bit 0 and 1)
                let xor:Short = ~(((self.LFSR & 0b10) >> 1) ^ (self.LFSR & 0b01))
                //store xor at corresponding bit according to noise width
                if(self.mmu.hasNoiseShortWidth()){
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
        }
        super.tick(masterCycles, frameCycles)
    }
    
    /// returns channel amplitude
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
