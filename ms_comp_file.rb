#2.1 Header
#struct StructuredStorageHeader
#{ // [offset from start in bytes, length in bytes]
#      BYTE _abSig[8]; // [000H,08] {0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1} for current version,
#                      // was {0x0e, 0x11, 0xfc, 0x0d, 0xd0, 0xcf, 0x11, 0xe0} on old, beta 2 files (late ’92)
#                      // which are also supported by the reference implementation
#      CLSID _clid; // [008H,16] class id (set with WriteClassStg, retrieved with GetClassFile/ReadClassStg)
#      USHORT _uMinorVersion; // [018H,02] minor version of the format: 33 is written by reference implementation
#      USHORT _uDllVersion; // [01AH,02] major version of the dll/format: 3 is written by reference implementation
#      USHORT _uByteOrder; // [01CH,02] 0xFFFE: indicates Intel byte-ordering
#      USHORT _uSectorShift; // [01EH,02] size of sectors in power-of-two (typically 9, indicating 512-byte sectors)
#      USHORT _uMiniSectorShift; // [020H,02] size of mini-sectors in power-of-two (typically 6, indicating 64-byte mini-sectors)
#      USHORT _usReserved; // [022H,02] reserved, must be zero
#      ULONG _ulReserved1; // [024H,04] reserved, must be zero
#      ULONG _ulReserved2; // [028H,04] reserved, must be zero
#      FSINDEX _csectFat; // [02CH,04] number of SECTs in the FAT chain
#      SECT _sectDirStart; // [030H,04] first SECT in the Directory chain
#      DFSIGNATURE _signature; // [034H,04] signature used for transactionin: must be zero. The reference implementation // does not support transactioning
#      ULONG _ulMiniSectorCutoff; // [038H,04] maximum size for mini-streams: typically 4096 bytes
#      SECT _sectMiniFatStart; // [03CH,04] first SECT in the mini-FAT chain
#      FSINDEX _csectMiniFat; // [040H,04] number of SECTs in the mini-FAT chain
#      SECT _sectDifStart; // [044H,04] first SECT in the DIF chain
#      FSINDEX _csectDif; // [048H,04] number of SECTs in the DIF chain
#      SECT _sectFat[109]; // [04CH,436] the SECTs of the first 109 FAT sectors };

class MsCompFile

StructuredStorageHeader = Struct.new(:abSig,:clid,:uMinorVersion,:uDllVersion,
                                     :uByteOrder,:uSectorShift,:uMiniSectorShift,
                                     :usReserved,:ulReserved1,:ulReserved2,:csectFat,
                                     :sectDirStart,:signature,:ulMiniSectorCutoff,
                                     :sectMiniFatStart,:csectMiniFat,:sectDifStart,
                                     :csectDif,:sectFat)

DirectoryEntry = Struct.new(:wcName, :usNameLen, :bObjType, :bColor,
                            :ulLeftSibling, :ulRightSibling, :ulChild,
                            :clid, :ulStateBits, :tsCreationTime, :tsModifiedTime,
                            :ulStartSector, :ullStreamSize)
  def initialize filename
    # open given filename & read SSH
    @ssh = StructuredStorageHeader.new

    @file = File.open(filename, 'rb')
      @ssh[:abSig] = @file.read(8).unpack('C8')
      @ssh[:clid] = @file.read(16).unpack('C16')
      @ssh[:uMinorVersion] = @file.read(2).unpack('S')[0]
      @ssh[:uDllVersion] = @file.read(2).unpack('S')[0]
      @ssh[:uByteOrder] = @file.read(2).unpack('S')[0]
      @ssh[:uSectorShift] = @file.read(2).unpack('S')[0]
      @ssh[:uMiniSectorShift] = @file.read(2).unpack('S')[0]
      @ssh[:usReserved] = @file.read(2).unpack('S')[0]
      @ssh[:ulReserved1] = @file.read(4).unpack('L')[0]
      @ssh[:ulReserved2] = @file.read(4).unpack('L')[0]
      @ssh[:csectFat] = @file.read(4).unpack('L')[0]
      @ssh[:sectDirStart] = @file.read(4).unpack('L')[0]
      @ssh[:signature] = @file.read(4).unpack('L')[0]
      @ssh[:ulMiniSectorCutoff] = @file.read(4).unpack('L')[0]
      @ssh[:sectMiniFatStart] = @file.read(4).unpack('L')[0]
      @ssh[:csectMiniFat] = @file.read(4).unpack('L')[0]
      @ssh[:sectDifStart] = @file.read(4).unpack('L')[0]
      @ssh[:csectDif] = @file.read(4).unpack('L')[0]
      @ssh[:sectFat] = @file.read(4*109).unpack('L109')
    # check for abSig
    if @ssh[:abSig].to_s!=[0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1].to_s
      raise "Given file signature invalid - not a MS Compound BF file!", caller
    end
    #puts @ssh.inspect
    @sectsize = 2**@ssh[:uSectorShift]
    #puts @sectsize
    # read FAT table
    @fat = []
    (1..@ssh[:csectFat]).each do |fidx|
      #puts 'FAT:%d' % fidx
      @file.seek( (@ssh[:sectFat][fidx-1]+1)*@sectsize , IO::SEEK_SET )
      @fat.concat(@file.read(@sectsize).unpack('L%d' % (@sectsize/4)))
    end

    # read miniFAT table
    @minifat = []
    (1..@ssh[:csectMiniFat]).each do |fidx|
      #puts 'miniFAT:%d' % fidx
      @file.seek( (@ssh[:sectMiniFatStart]+fidx)*@sectsize , IO::SEEK_SET )
      @minifat.concat(@file.read(@sectsize).unpack('L%d' % (@sectsize/4)))
    end

    #puts @fat.inspect

    # read directory entries
    @dir = []
    @cDirEntries = 0
      # seek to DirectoryEntries location
    @file.seek( @fat[@ssh[:sectDirStart]]*@sectsize, IO::SEEK_SET )
    nxt = @ssh[:sectDirStart]
    while nxt!=0xFFFFFFFE do
      (1..2).each do |x|
        @dir[@cDirEntries] = DirectoryEntry.new
        @dir[@cDirEntries][:wcName] = @file.read(64).force_encoding('UTF-16LE').encode('UTF-8')
        @dir[@cDirEntries][:wcName] = @dir[@cDirEntries][:wcName][0..@dir[@cDirEntries][:wcName].index("\u0000")-1]
        @dir[@cDirEntries][:usNameLen] = @file.read(2).unpack('S')[0]
        @dir[@cDirEntries][:bObjType] = @file.read(1).unpack('C')[0]
        @dir[@cDirEntries][:bColor] = @file.read(1).unpack('C')[0]
        @dir[@cDirEntries][:ulLeftSibling] = @file.read(4).unpack('L')[0]
        @dir[@cDirEntries][:ulRightSibling] = @file.read(4).unpack('L')[0]
        @dir[@cDirEntries][:ulChild] = @file.read(4).unpack('L')[0]
        @dir[@cDirEntries][:clid] = @file.read(16).unpack('C16')
        @dir[@cDirEntries][:ulStateBits] = @file.read(4).unpack('L')[0]
        @dir[@cDirEntries][:tsCreationTime] = @file.read(8).unpack('Q')[0]
        @dir[@cDirEntries][:tsModifiedTime] = @file.read(8).unpack('Q')[0]
        @dir[@cDirEntries][:ulStartSector] = @file.read(4).unpack('L')[0]
        @dir[@cDirEntries][:ullStreamSize] = @file.read(8).unpack('Q')[0]
        @cDirEntries+=1
      end
      nxt = @fat[nxt]
    end
  end

  # read entry starting at sectStart, following chain in FAT table, returns data
  def read_entry sectStart, uptoSize
    buf = ''
    nxt = sectStart
    while nxt!=0xFFFFFFFE do
      #puts "SECT: | #{nxt} -> FAT[nxt]=#{@fat[nxt]} | #{buf.length}"
      @file.seek((nxt+1)*@sectsize, IO::SEEK_SET)
      buf << @file.read(512)
      nxt = @fat[nxt]
    end
    return buf[0..uptoSize-1]
  end

  def entry_idx ename
    @dir.each_index do |i|
      return i if @dir[i][:wcName]==ename
    end
    raise 'Entry |%s| not found' % ename
    return nil
  end

  def dir_entry eid
    return @dir[eid] if eid.is_a?(Integer)
    return @dir[entry_idx(eid)] if eid.is_a?(String)
    raise 'Unknown parameter type |%s|' % eid.class
    return nil
  end

  def read_from eid
    idx = eid if eid.is_a?(Integer)
    idx = entry_idx(eid) if eid.is_a?(String)
    read_entry @dir[idx][:ulStartSector], @dir[idx][:ullStreamSize]
    #@file.seek( @fat[@dir[idx][:ulStartSector]]*@sectsize, IO::SEEK_SET )
    #@file.read(@dir[idx][:ullStreamSize])
  end

  attr_reader :fat
  attr_reader :minifat
  attr_reader :dir

end
