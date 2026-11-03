/*
 * G513RM: fake EC device for macOS (real EC0 stays active for battery) + USBX power.
 * Real EC lives at \_SB.PCI0.SBRG.EC0.
 */
DefinitionBlock ("", "SSDT", 2, "G513", "SsdtEC", 0x00001000)
{
    External (_SB_.PCI0.SBRG, DeviceObj)

    Scope (\_SB.PCI0.SBRG)
    {
        Device (EC)
        {
            Name (_HID, "ACID0001")
            Method (_STA, 0, NotSerialized)
            {
                If (_OSI ("Darwin"))
                {
                    Return (0x0F)
                }
                Return (Zero)
            }
        }
    }

    Scope (\_SB)
    {
        Device (USBX)
        {
            Name (_ADR, Zero)
            Method (_DSM, 4, NotSerialized)
            {
                If (LEqual (Arg2, Zero))
                {
                    Return (Buffer (One) { 0x03 })
                }
                Return (Package ()
                {
                    "kUSBSleepPortCurrentLimit", 1500,
                    "kUSBWakePortCurrentLimit", 1500
                })
            }
            Method (_STA, 0, NotSerialized)
            {
                If (_OSI ("Darwin"))
                {
                    Return (0x0F)
                }
                Return (Zero)
            }
        }
    }
}
