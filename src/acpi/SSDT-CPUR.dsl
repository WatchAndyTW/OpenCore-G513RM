/*
 * G513RM: the firmware declares CPUs as Device (ACPI0007) objects under \_SB.PLTF (P000-P00F);
 * macOS needs legacy Processor objects. One per thread (16 on the 6900HX).
 */
DefinitionBlock ("", "SSDT", 2, "G513", "CPUR", 0x00003000)
{
    External (_SB_.PLTF.P000, DeviceObj)
    External (_SB_.PLTF.P001, DeviceObj)
    External (_SB_.PLTF.P002, DeviceObj)
    External (_SB_.PLTF.P003, DeviceObj)
    External (_SB_.PLTF.P004, DeviceObj)
    External (_SB_.PLTF.P005, DeviceObj)
    External (_SB_.PLTF.P006, DeviceObj)
    External (_SB_.PLTF.P007, DeviceObj)
    External (_SB_.PLTF.P008, DeviceObj)
    External (_SB_.PLTF.P009, DeviceObj)
    External (_SB_.PLTF.P00A, DeviceObj)
    External (_SB_.PLTF.P00B, DeviceObj)
    External (_SB_.PLTF.P00C, DeviceObj)
    External (_SB_.PLTF.P00D, DeviceObj)
    External (_SB_.PLTF.P00E, DeviceObj)
    External (_SB_.PLTF.P00F, DeviceObj)

    Scope (\_SB)
    {
        Processor (PR00, 0x01, 0x00000810, 0x06)
        {
            Return (\_SB.PLTF.P000)
        }
        Processor (PR01, 0x02, 0x00000810, 0x06)
        {
            Return (\_SB.PLTF.P001)
        }
        Processor (PR02, 0x03, 0x00000810, 0x06)
        {
            Return (\_SB.PLTF.P002)
        }
        Processor (PR03, 0x04, 0x00000810, 0x06)
        {
            Return (\_SB.PLTF.P003)
        }
        Processor (PR04, 0x05, 0x00000810, 0x06)
        {
            Return (\_SB.PLTF.P004)
        }
        Processor (PR05, 0x06, 0x00000810, 0x06)
        {
            Return (\_SB.PLTF.P005)
        }
        Processor (PR06, 0x07, 0x00000810, 0x06)
        {
            Return (\_SB.PLTF.P006)
        }
        Processor (PR07, 0x08, 0x00000810, 0x06)
        {
            Return (\_SB.PLTF.P007)
        }
        Processor (PR08, 0x09, 0x00000810, 0x06)
        {
            Return (\_SB.PLTF.P008)
        }
        Processor (PR09, 0x0A, 0x00000810, 0x06)
        {
            Return (\_SB.PLTF.P009)
        }
        Processor (PR0A, 0x0B, 0x00000810, 0x06)
        {
            Return (\_SB.PLTF.P00A)
        }
        Processor (PR0B, 0x0C, 0x00000810, 0x06)
        {
            Return (\_SB.PLTF.P00B)
        }
        Processor (PR0C, 0x0D, 0x00000810, 0x06)
        {
            Return (\_SB.PLTF.P00C)
        }
        Processor (PR0D, 0x0E, 0x00000810, 0x06)
        {
            Return (\_SB.PLTF.P00D)
        }
        Processor (PR0E, 0x0F, 0x00000810, 0x06)
        {
            Return (\_SB.PLTF.P00E)
        }
        Processor (PR0F, 0x10, 0x00000810, 0x06)
        {
            Return (\_SB.PLTF.P00F)
        }
    }
}
