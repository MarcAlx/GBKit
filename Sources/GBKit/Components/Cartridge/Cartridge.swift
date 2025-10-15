import Foundation

public class Cartridge: Describable {
    
    private var source:Data = Data()
    private var data:[Byte] = []
    
    public subscript(address:Short) -> Byte {
        get {
            self.bankController[address]
        }
        set {
            self.bankController[address] =  newValue
        }
    }
    
    ///headers of the cartridge read from ROM
    public private(set) var headers:CartridgeHeader = CartridgeHeader()
    
    public private(set) var bankController:MBC = MBC(type: .ROM_ONLY, banks: [])
    
    public init() {}
    
    ///init cartridge from ROM data
    public init(data:Data) throws {
        self.source = data
        self.data = self.source.toArray()
        self.headers = try CartridgeHeader(cartridgeData: self.data)
        let banks = self.buildBanks()
        self.bankController = MBC(type: self.headers.cartridgeType, banks: banks)
    }
    
    /// init banks from data
    private func buildBanks() -> [MemoryBank] {
        var banks:[MemoryBank] = []
        for i in 0..<self.headers.nbBankInROM {
            let from = i * GBConstants.ROMBankSizeInBytes
            let to   = (i+1) * GBConstants.ROMBankSizeInBytes
            banks.append(MemoryBank(data:Array(self.data[from..<to])))
        }
        return banks;
    }
    
    public func describe() -> String {
        return """
        Title: \(self.headers.title)
        Manufacturer code: \(self.headers.manufacturerCode ?? "")
        Licensee: \(self.headers.licensee ?? "unknown")
        Destination: \(String(reflecting: self.headers.destination))
        Version: \(self.headers.versionNumber)
        
        Cartridge type: \(String(reflecting: self.headers.cartridgeType))
        ROM: \(self.headers.romSize)KiB (\(self.headers.nbBankInROM) banks)
        RAM: \(self.headers.ramSize)KiB (\(self.headers.nbBankInRAM) banks)
        CGB support: \(self.headers.cgbFlag != nil ? String(reflecting: self.headers.cgbFlag) : "unspecified" )
        
        Nintendo logo in headers: \(self.headers.isNintendoLogoPresent)
        
        Header checksum: \(self.headers.headerChecksum) (computed: \(self.headers.headerChecksumComputed), equals: \(self.headers.headerChecksum==self.headers.headerChecksumComputed))
        Global checksum: \(self.headers.checksum) (computed: \(self.headers.checksumComputed), equals: \(self.headers.checksum==self.headers.checksumComputed))
        """
    }
}
