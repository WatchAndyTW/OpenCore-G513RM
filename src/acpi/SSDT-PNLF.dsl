/*
 * Backlight device for macOS (AppleBacklight / BrightnessKeys), G513RM.
 * Same as the published G513RM EFI's SSDT-PNLF: no GPU registers, Darwin only.
 */
DefinitionBlock ("", "SSDT", 2, "G513RM", "PNLF", 0x00000000)
{
    Device (PNLF)
    {
        Name (_HID, EisaId ("APP0002"))
        Name (_CID, "backlight")
        Name (_UID, 0x13)
        Method (_STA, 0, NotSerialized)
        {
            If (_OSI ("Darwin"))
            {
                Return (0x0B)
            }
            Else
            {
                Return (Zero)
            }
        }
    }
}
