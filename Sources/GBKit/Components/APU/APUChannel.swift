/// common properties of an APU channel
public protocol APUChannel: Component, Clockable {    
    /// can be seen as channel value
    var amplitude:Byte { get }
    
    /// amplitude once processed by DAC
    var analogAmplitude:Float { get }
    
    /// true if enabled
    var enabled:Bool { get set }
    
    ///channel id
    var id:AudioChannelId { get }
    
    /// causes this channel to trigger
    func trigger()
}

/// channel that supports length control
public protocol LengthableChannel {
    /// timer for length
    var lengthTimer:Int {get set}
    
    /// tick length
    func tickLength()
}

/// channel that supports sweep control
public protocol SweepableChannel {
    /// tick sweep
    func tickSweep()
}

/// channel that supports volume control
public protocol VolumableChannel {
    //volume is not something ticked, this protocol is mainly there for typing
}

/// channel that supports period
public protocol PeriodicChannel {
    ///channel id
    var periodId:ChannelWithPeriodId { get }
}

/// channel that supports envelope control
public protocol EnveloppableChannel {
    ///channel id
    var envelopeId:EnveloppableAudioChannelId { get }
    
    /// tick volume
    func tickEnvelope()
}

/// an audio channel is clockable component with length, since all channel have Length cover it in protocol class
public protocol CoreAudioChannel: Component,
                                  APUChannel,
                                  Clockable,
                                  LengthableChannel{
    ///register an APU for further usage
    func registerAPU(apu: APUProxy)
}

/// square1 channel support length and envelope control
public protocol SquareChannel: CoreAudioChannel, PeriodicChannel, LengthableChannel, EnveloppableChannel {
    ///square id
    var squareId:DutyAudioChannelId { get }
}

/// square2 channel  support length and envelope control along with sweep control
public protocol SquareWithSweepChannel: CoreAudioChannel, PeriodicChannel, LengthableChannel, EnveloppableChannel, SweepableChannel {
}

/// wave channel supports length and volume control
public protocol WaveChannel: CoreAudioChannel, PeriodicChannel, LengthableChannel, VolumableChannel {
}

/// noise channel supports length and envelope control
public protocol NoiseChannel: CoreAudioChannel, LengthableChannel, EnveloppableChannel {
}
