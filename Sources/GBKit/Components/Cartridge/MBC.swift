/// MBC banking mode
enum MBCBankingMode:Byte {
    /// simple ROM control
    case SIMPLE = 0
    /// advanced RAM control
    case ADVANCED = 1
}

/// Memory Bank Controller
public class MBC: Component {
    
    ///cartridge type for ref
    public private(set) var type:CartridgeType
    
    ///cartridge banks
    private(set) var banks:[MemoryBank] = []
    
    ///external ram
    private(set) var externalRAM:[MemoryBank] = []
    
    /// true if ram is enabled
    private(set) var ramEnabled:Bool = false
    
    /// true if ram is enabled
    private(set) var bankingMode:MBCBankingMode = MBCBankingMode.SIMPLE
    
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
    private var switchableROMBankIndex:Int = 1
    
    /// index of the external ram bank to use for switachble area
    private var switchableRAMBankIndex:Int = 1
    
    ///the mapper itself, dispatch R/W to correct cartridge banks
    public subscript(address:Short) -> Byte {
        get {
            switch(address){
            case MMUAddressSpaces.CARTRIDGE_BANK0:
                return self.banks[0][address]
            case MMUAddressSpaces.CARTRIDGE_SWITCHABLE_BANK:
                return self.banks[self.switchableROMBankIndex][address-0x4000]
            case MMUAddressSpaces.EXTERNAL_RAM_BANK:
                if(self.ramEnabled){
                    if(self.type != .MBC2 && self.type != .MBC2_BATTERY){
                        return self.externalRAM[self.switchableRAMBankIndex][address-0xA000]
                    }
                    else {
                        return self.externalRAM[self.switchableRAMBankIndex][address & 0x01FF] | 0xF0
                    }
                }
                return 0xFF
            default:
                return 0xFF
            }
        }
        set {
            switch(address){
            //writing to ROM controls mapper
            case MMUAddressSpaces.CARTRIDGE_ROM:
                self.handleROMWrite(addr: address, val: newValue)
                break
            case MMUAddressSpaces.EXTERNAL_RAM_BANK:
                if(self.ramEnabled){
                    if(self.type != .MBC2 && self.type != .MBC2_BATTERY){
                        self.externalRAM[self.switchableRAMBankIndex][address-0xA000] = newValue
                    }
                    else {
                        self.externalRAM[self.switchableRAMBankIndex][address & 0x01FF] = newValue & 0xF
                    }
                }
                break
            default:
                break
            }
        }
    }
    
    init(type:CartridgeType, banks:[MemoryBank], externalRAM:[MemoryBank]){
        self.type=type
        self.banks=banks
        self.externalRAM = externalRAM
        self.switchableROMBankIndex=1
    }
    
    /// handle write to rom, mainly switchable bank control
    private func handleROMWrite(addr:Short, val:Byte){
        if(self.type == .MBC1
        || self.type == .MBC1_RAM
        || self.type == .MBC1_RAM_BATTERY) {
            switch addr {
            case MBCControlAddressSpaces.MBC1_RAM_ENABLE:
                //writing A in lsb should enable ram
                self.ramEnabled = (val & 0xA) > 0
                break
            case MBCControlAddressSpaces.MBC1_ROM_BANK_SELECT:
                //switch
                self.switchableROMBankIndex = self.getBankIndex(fromVal: val, mask: 0b0001_1111, nbOfBanks: self.banks.count)
                break;
            case MBCControlAddressSpaces.MBC1_RAM_BANK_SELECT:
                //only first 2 bits matter
                let bits2Keep = (val & 0b0000_0011)
                
                if(self.bankingMode == MBCBankingMode.SIMPLE){
                    //in simple mode, the 2 bits mean upper bits of rom bank index
                    self.switchableROMBankIndex = self.switchableROMBankIndex | Int((bits2Keep << 5))
                }
                else if(self.bankingMode == MBCBankingMode.ADVANCED){
                    //in advanced mode, the 2 bits mean RAM bank index
                    self.switchableRAMBankIndex = Int(bits2Keep)
                }
                
                break;
            case MBCControlAddressSpaces.MBC1_BANKING_MODE_SELECT:
                self.bankingMode = MBCBankingMode(rawValue:(0b0000_0001 & val))!
                break;
            default:
                break
            }
        }
        else if(self.type == .MBC2
             || self.type == .MBC2_BATTERY) {
            if(isBitSet(ShortMask.Bit_8, addr)){
                self.switchableROMBankIndex = self.getBankIndex(fromVal: val, mask: 0b0000_1111, nbOfBanks: self.banks.count)
            }
            else {
                self.ramEnabled = (val & 0xF) == 0x0A
                self.switchableRAMBankIndex = 0
            }
        }
        else if(self.type == .MBC3
             || self.type == .MBC3_RAM
             || self.type == .MBC3_RAM_BATTERY
             || self.type == .MBC3_TIMER_BATTERY
             || self.type == .MBC3_TIMER_RAM_BATTERY) {
            switch addr {
            case MBCControlAddressSpaces.MBC3_RAM_TIMER_ENABLE:
                //writing A in lsb should enable ram
                self.ramEnabled = (val & 0x0F) == 0x0A
                
                //TODO RTC
                break
            case MBCControlAddressSpaces.MBC3_ROM_BANK_SELECT:
                //switch
                self.switchableROMBankIndex = self.getBankIndex(fromVal: val, mask: 0b0111_1111, nbOfBanks: self.banks.count)
                break;
            case MBCControlAddressSpaces.MBC3_RAM_BANK_RTC_REG_SELECT:
                if (0x00...0x03).contains(val) {
                    self.switchableRAMBankIndex = Int(val)
                }
                else if (0x08...0x0C).contains(val) {
                    //TODO RTC
                }
            case MBCControlAddressSpaces.MBC3_LATCH_LOCK:
                //TODO RTC
                break
            default:
                break;
            }
        }
        else if(self.type == .MBC5
             || self.type == .MBC5_RAM
             || self.type == .MBC5_RAM_BATTERY
             || self.type == .MBC5_RUMBLE
             || self.type == .MBC5_RUMBLE_RAM
             || self.type == .MBC5_RUMBLE_RAM_BATTERY) {
            switch addr {
            case MBCControlAddressSpaces.MBC5_RAM_ENABLE:
                //writing A in lsb should enable ram
                self.ramEnabled = (val & 0x0F) == 0x0A
                break
            case MBCControlAddressSpaces.MBC5_ROM_BANK_LOW:
                //switch
                self.switchableROMBankIndex = Int(val)
                break;
            case MBCControlAddressSpaces.MBC5_ROM_BANK_HIGH:
                //add 9th bit
                self.switchableROMBankIndex = (((Int(val) & 0b0000_0001) << 8) | (self.switchableROMBankIndex & 0xFF))
                if banks.count > 0 {
                    self.switchableROMBankIndex %= banks.count
                }
                break;
            case MBCControlAddressSpaces.MBC5_RAM_BANK_SELECT:
                if (0x00...0x0F).contains(val) {
                    let bank = Int(val)
                    if bank < self.externalRAM.count {
                        self.switchableRAMBankIndex = bank
                    }
                }
                break
            default:
                break;
            }
        }
    }
    
    /// determine bank index from a byte value,  a range of byte to consider and a number of banks
    private func getBankIndex(fromVal:Byte, mask:Byte, nbOfBanks:Int) -> Int {
        var bank = Int(fromVal & mask)
        //0 should map to 1
        if (bank == 0) {
            bank = 1
        }
        //avoid OOB
        bank = bank % nbOfBanks
        return bank
    }
    
    public func reset() {
        self.ramEnabled = false;
    }
}
