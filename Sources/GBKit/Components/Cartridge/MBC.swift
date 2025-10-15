/// Memory Bank Controller
public struct MBC {
    ///cartridge type for ref
    public private(set) var type:CartridgeType
    
    ///cartridge banks
    private(set) var banks:[MemoryBank] = []
    
    //private let externalRam:MemoryBank = MemoryBank(size: GBConstants.ExternalRAMSize,name: "external-ram")
    
    /// true if cartridge has embedded RAM
    public var hasRAM:Bool {
        get{
            switch self.type {
                 case .MBC1_RAM, .MBC1_RAM_BATTERY,
                      .MBC2, .MBC2_BATTERY,
                      .ROM_RAM, .ROM_RAM_BATTERY,
                      .MMM01_RAM, .MMM01_RAM_BATTERY,
                      .MBC3_RAM, .MBC3_TIMER_RAM_BATTERY, .MBC3_RAM_BATTERY,
                      .MBC5_RAM, .MBC5_RAM_BATTERY, .MBC5_RUMBLE_RAM, .MBC5_RUMBLE_RAM_BATTERY,
                      .MBC7_SENSOR_RUMBLE_RAM_BATTERY,
                      .POCKET_CAMERA,
                      .HuC1_RAM_BATTERY, .HuC3:
                true
            default:
                false
            }
        }
    }
    
    /// true if cartridge has a battery
    public var hasBattery:Bool {
        get {
            switch self.type {
                 case .MBC1_RAM_BATTERY,
                      .MBC2_BATTERY,
                      .ROM_RAM_BATTERY,
                      .MMM01_RAM_BATTERY,
                      .MBC3_RAM_BATTERY, .MBC3_TIMER_RAM_BATTERY,
                      .MBC5_RAM_BATTERY, .MBC5_RUMBLE_RAM_BATTERY,
                      .MBC7_SENSOR_RUMBLE_RAM_BATTERY,
                      .POCKET_CAMERA,
                      .HuC1_RAM_BATTERY, .HuC3:
                true
            default:
                false
            }
        }
    }
    
    /// true if real time clock supported
    public var hasRTC:Bool {
        get {
            switch self.type {
                 case .MBC3_TIMER_BATTERY, .MBC3_TIMER_RAM_BATTERY,
                      .HuC3:
                true
            default:
                false
            }
        }
    }
    
    /// true cartrigde can rumble
    public var hasRumble:Bool {
        get {
            switch self.type {
                 case .MBC5_RUMBLE, .MBC5_RUMBLE_RAM, .MBC5_RUMBLE_RAM_BATTERY,
                      .MBC7_SENSOR_RUMBLE_RAM_BATTERY,
                      .HuC3:
                true
            default:
                false
            }
        }
    }
    
    /// index of the bank to use for switachble area
    private var switchableBankIndex:Int = 1
    
    ///the mapper itself, dispatch R/W to correct cartridge banks
    public subscript(address:Short) -> Byte {
        get {
            switch(address){
            case MMUAddressSpaces.CARTRIDGE_BANK0:
                return self.banks[0][address]
            case MMUAddressSpaces.CARTRIDGE_SWITCHABLE_BANK:
                return self.banks[self.switchableBankIndex][address-0x4000]
            case MMUAddressSpaces.EXTERNAL_RAM_BANK:
                return 0xFF //todo handle external ram
            default:
                return 0xFF
            }
        }
        set {
            switch(address){
            //bank 0 is read only
            case MMUAddressSpaces.CARTRIDGE_BANK0:
                break
            //switchable bank, switch bank on write
            case MMUAddressSpaces.CARTRIDGE_SWITCHABLE_BANK:
                self.handleROMWrite(val: newValue)
                break
            case MMUAddressSpaces.EXTERNAL_RAM_BANK:
            //TODO handle external ram bank write
                break
            default:
                break
            }
        }
    }
    
    init(type:CartridgeType, banks:[MemoryBank]){
        self.type=type
        self.banks=banks
        self.switchableBankIndex=1
    }
    
    /// handle write to rom, mainly switchable bank control
    private func handleROMWrite(val:Byte){
        //TODO change self.switchableBankIndex
    }
}
