/// maps Timer clock mode to its corresponding M cycle frequency
let TimerClockModeToFrequency:[Int] = [
    256, // 0b00
    4,   // 0b01
    16,  // 0b10
    64   // 0b11
]

/// maps Timer clock mode to its corresponding M cycle frequency
let TimerClockModeToFaillingEdgeBit:[ShortMask] = [
    ShortMask.Bit_9, // 0b00
    ShortMask.Bit_3, // 0b01
    ShortMask.Bit_5, // 0b10
    ShortMask.Bit_7  // 0b11
]

///ease timer related access
public protocol TimerInterface {
    ///16bit counter used to render DIV (not exposed on real game boy, yet used)
    var INTERNAL_DIV_COUNTER:Short { get }
    
    ///ease access to DIV
    var DIV:Byte { get }
    
    ///ease access to TMA
    var TMA:Byte { get }
    
    ///ease access to TIMA
    var TIMA:Byte { get set }
    
    ///ease access to DIV
    var TAC:Byte { get }
}

///wraps timer logic
public class Timer : Component, Clockable {
    private let mmu:MMU
    private let interrupts:InterruptsControlInterface
    private var overflowPending = false
    
    public init(mmu: MMU) {
        self.mmu = mmu
        self.interrupts = mmu
    }
    
    ///cycles this clock has elapsed
    public private(set) var cycles: Int = 0
    
    ///clock mode extract from timer control TAC
    private var clockMode:Int {
        get {
            return Int(self.mmu.TAC & 0b0000_0011 /*keep only first two bits*/)
        }
    }
    
    /// perform a single tick on a clock, masterCycles and frameCycles  are provided for synchronisation purpose
    public func tick(_ masterCycles:Int, _ frameCycles:Int) -> Void {
        let oldFallingEdgeBitSet = isBitSet(TimerClockModeToFaillingEdgeBit[self.clockMode], self.mmu.INTERNAL_DIV_COUNTER)
        self.mmu.INTERNAL_DIV_COUNTER = self.mmu.INTERNAL_DIV_COUNTER &+ 4
        let newFallingEdgeBitSet = isBitSet(TimerClockModeToFaillingEdgeBit[self.clockMode], self.mmu.INTERNAL_DIV_COUNTER)
        
        //n.b DIV will increment at 256 cycles as only 8 upper bits of INTERNAL_DIV_COUNTER are considered as DIV,
        //    so it will take 256 INTERNAL_DIV_COUNTER tick to have DIV incremented by 1
        
        let tacEnabled:Bool = isBitSet(.Bit_2, self.mmu[IOAddresses.TAC.rawValue])
        
        
        //we have wait 1 cycle during overflow -> trigger interrup
        if(overflowPending){
            //timer modulo
            self.mmu.TIMA = self.mmu.TMA
            //trigger interrupt
            self.interrupts.setInterruptFlagValue(.Timer, true)
            //reset
            self.overflowPending = false
        }
        
        //tac enabled and edge bit has fallen (from 1 to 0)
        if(tacEnabled && oldFallingEdgeBitSet && !newFallingEdgeBitSet) {
            //TIMA will overflow by adding 1 -> reset TIMA with TMA and trigger interrupt
            if(self.mmu.TIMA == 0xFF){
                self.overflowPending = true
            }
            else {
                self.mmu.TIMA = self.mmu.TIMA &+ 1
            }
        }
        
        self.cycles = self.cycles &+ GBConstants.MCycleLength
    }
    
    public func reset(){
    }
}
