

require 'bindata'
require 'ms_frfl97'

class MsFIB < BinData::Record
  endian :little

    struct :fibBase do
      endian :little
      uint16 :wIdent
      uint16 :nFib
      uint16 :unused
      uint16 :lid
      uint16 :pnNext
      #uint16 :bfA
      struct :bfA do  #bitfield A  f812 -> 12F8 -> 0001 0010 1111 1000
        endian :little

        bit4 :cQuickSaves
        bit1 :fHasPic
        bit1 :fComplex
        bit1 :fGlsy
        bit1 :fDot

        bit1 :fObfuscated
        bit1 :fFarEast
        bit1 :fLoadOverride
        bit1 :fExtChar
        bit1 :fWriteReservation
        bit1 :fReadOnlyRecommended
        bit1 :fWhichTblStm
        bit1 :fEncrypted
      end
      uint16 :nFibBack
      uint32 :lkey
      uint8 :envr
      #uint8 :bfB
      struct :bfB do  #bitfield B
        endian :little
        bit1 :fMac
        bit1 :fEmptySpecial
        bit1 :fLoadOverridePage
        bit1 :reserved1
        bit4 :res_spare
      end
      uint16 :reserved3
      uint16 :reserved4
      uint32 :reserved5
      uint32 :reserved6
    end #endof... FibBase

    uint16 :csw     # specifies the length in #uint16s of fibRgW97 (must be 0x0e=14d)
    struct :fibRgW97 do
      endian :little
      uint16 :reserved1
      uint16 :reserved2
      uint16 :reserved3
      uint16 :reserved4
      uint16 :reserved5
      uint16 :reserved6
      uint16 :reserved7
      uint16 :reserved8
      uint16 :reserved9
      uint16 :reserved10
      uint16 :reserved11
      uint16 :reserved12
      uint16 :reserved13
      uint16 :lidFE     # Locale-ID of stored style names, true if fFarEast==1
    end
    uint16 :cslw
    struct :fibRgLw97 do
      endian :little
      uint32 :cbMac
      uint32 :reserved1
      uint32 :reserved2
      uint32 :ccpText
      uint32 :ccpFtn
      uint32 :ccpHdd
      uint32 :ccpMcr
      uint32 :ccpAtn
      uint32 :ccpEdn
      uint32 :ccpTxbx
      uint32 :ccpHdrTxbx
      uint32 :reserved4
      uint32 :reserved5
      uint32 :reserved6
      uint32 :reserved7
      uint32 :reserved8
      uint32 :reserved9
      uint32 :reserved10
      uint32 :reserved11
      uint32 :reserved12
      uint32 :reserved13
      uint32 :reserved14
    end
    uint16 :cbRgFcLcb   # indicator & length-of (no of QWORDs!) what structure comes next :
    FibRgFcLcb97 :fibRgFcLcbBlob
end
