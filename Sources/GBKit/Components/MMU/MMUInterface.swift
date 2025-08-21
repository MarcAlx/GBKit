/// class that can relay some MMU read/write
public protocol MMUInterface {
    /// read a Byte from MMU
    func read(address:Short) -> Byte

    /// write a Byte to MMU
    func write(address:Short, value:Byte)
}
